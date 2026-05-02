# 課題3: 暗号資産マイニング通信と過剰なIAM権限（Cloud層）

**難易度:** ★★★  
**対象ファイル:** `terraform/iam.tf`, `terraform/vpc.tf`

---

## シナリオ

ホストノードに侵入した攻撃者が、AWSのAPIを叩いて大量のEC2インスタンスを起動しようとしています。  
また、外部の不審なIPへ暗号資産マイニングプール（`stratum+tcp://pool.example.com:3333`）への通信が行われています。  
ネットワークのアクセス制御と、アプリケーションが持つAWS権限（IAM）の設計を見直してください。

---

## 攻撃シナリオ

```
課題2でホストノードに侵入済みの攻撃者
  │
  ├─ [1] EC2インスタンスメタデータサービス（IMDS）へのアクセス
  │       curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
  │       → IAMロール名を取得
  │       curl http://169.254.169.254/latest/meta-data/iam/security-credentials/eks-node-role
  │       → AccessKeyId / SecretAccessKey / Token を取得！
  │
  ├─ [2] 過剰なIAM権限を利用
  │       export AWS_ACCESS_KEY_ID=...（取得したクレデンシャルをセット）
  │       aws ec2 run-instances --count 100 --instance-type p3.16xlarge
  │       → 大量のGPUインスタンスを起動（クリプトマイニング用）
  │
  ├─ [3] S3バケットへのアクセス
  │       aws s3 ls  → 全バケットを列挙
  │       aws s3 cp s3://sensitive-bucket/ . --recursive
  │       → 機密データを外部に持ち出し
  │
  └─ [4] 外部への不審な通信
          Security Groupにアウトバウンド制限がないため
          → stratum+tcp://pool.example.com:3333 への通信が成立
          → マイニングプールと通信しながら不正採掘
```

---

## 調査手順

### Step 1: IMDSへのアクセス確認

```bash
# PodからIMDSにアクセスできるか確認（SSRFシミュレーション）
kubectl exec -it -n dojo deploy/backend -- /bin/sh

# コンテナ内で実行
curl -s http://169.254.169.254/latest/meta-data/
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

**確認ポイント:** IMDSv1が有効だとTokenなしで即座にクレデンシャルが取得できる

### Step 2: IAMポリシーの確認（Terraform）

```bash
cat terraform/iam.tf
```

**確認ポイント:**
- `AdministratorAccess` が付与されていませんか？
- `Action: "*"` や `Resource: "*"` のポリシーはありますか？

### Step 3: VPC/Security Groupの確認

```bash
cat terraform/vpc.tf
```

**確認ポイント:**
- Security GroupのEgressルールで `0.0.0.0/0` への全トラフィックが許可されていませんか？
- `metadata_options` の設定はどうなっていますか？

### Step 4: LocalStackでシミュレーション

```bash
# LocalStackを起動
docker compose up -d localstack

# Terraformを初期化・apply
cd terraform
terraform init
terraform apply -auto-approve

# 作成されたIAMポリシーを確認
aws --endpoint-url=http://localhost:4566 iam list-policies --scope Local
aws --endpoint-url=http://localhost:4566 iam get-policy-version \
  --policy-arn arn:aws:iam::000000000000:policy/app-overpermissive-policy \
  --version-id v1
```

---

## 問題の整理

| 問題 | 場所 | リスク |
|------|------|--------|
| `AdministratorAccess` をNodeに付与 | `iam.tf:L18-21` | 全AWSリソースを操作可能 |
| `Action: "*", Resource: "*"` | `iam.tf:L30-37` | 権限昇格・全操作が可能 |
| EgressがAll Allow | `vpc.tf:L56-62` | 外部マイニングプールへの通信が可能 |
| IMDSv1が有効（デフォルト） | `vpc.tf:L79以降` | SSRFで一時クレデンシャルを窃取可能 |
| パブリックサブネットにNode配置 | `vpc.tf:L21-31` | ノードが直接インターネットに露出 |
| K8s API エンドポイントが全IP公開 | `eks.tf:L11` | インターネットからAPIサーバーにアクセス可能 |

---

## 修正方針

### 1. IMDSv2を強制（最重要）

```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"  # IMDSv2強制
  http_put_response_hop_limit = 1           # コンテナからのアクセスを防止
}
```

IMDSv2ではPUT→GETの2ステップが必要なため、SSRFによる直接アクセスを防止できます。

### 2. IAM最小権限 + IRSA

```
NodeのIAMロール: EKS Nodeの動作に必要な最小限のみ
  - AmazonEKSWorkerNodePolicy
  - AmazonEKS_CNI_Policy
  - AmazonEC2ContainerRegistryReadOnly

各PodのAWS権限: IRSA（IAM Roles for Service Accounts）で分離
  - backend-sa → Secrets Manager の読み取り権限のみ
```

IRSA導入後、K8s ServiceAccountにIAM Role ARNをアノテーションで指定:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  namespace: dojo
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/backend-irsa-role
```

### 3. Network Policyで外部通信をブロック

```yaml
# Egressを必要最小限に制限（詳細はnetwork-policy.yamlを参照）
egress:
  - to: [postgres-svc のみ]
  - to: [DNS (UDP:53) のみ]
# → マイニングプールへの通信はブロックされる
```

### 4. Security Groupのハードニング

```hcl
egress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # HTTPS（AWS API）のみ
}
# 3333番ポートなどへのアウトバウンドを明示的にブロック
```

---

## 解答例

- `answers/terraform/iam-fixed.tf`
- `answers/terraform/vpc-fixed.tf`
- `answers/k8s/network-policy.yaml`

---

## 学習のまとめ

### Blast Radius（被害範囲）の最小化

- **NodeレベルのIAM権限**: K8s Node自体はNodePolicyの最小限のみ
- **PodレベルのIAM権限**: IRSAで各Podに必要最小限のみ付与
- 万が一1つのPodが侵害されても、被害が他のPodやAWSリソースに波及しない設計

### 多層防御（Defense in Depth）

```
[攻撃者]
  → ① K8s Network Policy で外部通信をブロック
  → ② Security Group でアウトバウンドを制限
  → ③ IMDSv2 でクレデンシャル窃取を困難に
  → ④ IRSA で窃取しても権限を最小化
```

どれか1層が突破されても、次の層で被害を食い止められる設計が重要です。

### 検知と対応

- **AWS CloudTrail**: 不審なAPIコールを記録
- **AWS GuardDuty**: 暗号資産マイニング活動を自動検知
- **Amazon Detective**: インシデント後の調査を支援
