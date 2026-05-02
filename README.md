# セキュリティ脆弱性対応道場

> 意図的に穴だらけのシステムを堅牢化しながらセキュリティ設計を学ぶ実践トレーニング環境

## この道場について

架空のスタートアップ企業が「スピード最優先」で構築した結果、致命的なセキュリティホールを抱えたまま稼働しているWebシステムを舞台にします。  
新たに参画したSREとして、この「意図的に壊れた環境」を調査し、攻撃者の視点に立ちながらシステムを堅牢化（ハードニング）していくミッションを担います。

### 学習内容

| レイヤー | テーマ | 難易度 |
|---|---|---|
| App層 | GitHubリポジトリからのクレデンシャル漏洩 | ★☆☆ |
| K8s/EKS層 | 特権コンテナからのホストノード乗っ取り | ★★☆ |
| Cloud層 | 過剰なIAM権限 + IMDSv1によるSSRF | ★★★ |

---

## ディレクトリ構成

```
secrity-training-dojo/
├── app/                    # 脆弱なNode.jsバックエンドAPI
│   ├── Dockerfile
│   ├── package.json
│   ├── config.js           # ⚠️ 課題1: クレデンシャルがハードコード
│   └── index.js
├── k8s/
│   ├── base/               # Kustomize ベース設定
│   └── overlays/
│       └── dev/            # ⚠️ 課題1,2: 脆弱な開発環境マニフェスト
├── terraform/              # ⚠️ 課題3: 過剰なIAM権限 / 不十分なVPC設定
│   ├── main.tf
│   ├── iam.tf
│   ├── vpc.tf
│   └── eks.tf
├── answers/                # 各課題の解答例（演習中は見ないこと！）
│   ├── k8s/
│   └── terraform/
├── docs/                   # 演習ガイドと技術解説
│   ├── 01_credential-leakage.md
│   ├── 02_privileged-container.md
│   └── 03_iam-overperms.md
├── docker-compose.yml      # ローカル脆弱環境の起動
├── kind-config.yaml        # kindクラスタ設定
└── Makefile
```

---

## セットアップ手順

### 前提条件

```bash
docker --version          # Docker 24.x 以上
docker compose version    # Docker Compose v2
kubectl version --client  # kubectl 1.28 以上
kind version              # kind 0.22 以上 (または minikube)
terraform version         # Terraform 1.6 以上
```

### 1. リポジトリのクローン

```bash
git clone https://github.com/givelab/secrity-training-dojo
cd secrity-training-dojo
```

### 2. 脆弱な環境のデプロイ

```bash
make apply-vulnerable-env
```

内部では以下を実行します:
1. kindでローカルK8sクラスタを作成
2. 脆弱なDockerイメージをビルドしてkindにロード
3. 脆弱なK8sマニフェストをapply

### 3. 稼働確認

```bash
# Podが全てRunningになっていることを確認
kubectl get pods -A

# フロントエンドアプリにアクセス
open http://localhost:8080
```

### 4. 環境のリセット

```bash
make clean
```

---

## 演習課題

各課題の詳細ガイドは `docs/` ディレクトリを参照してください。

- [課題1: クレデンシャル漏洩](docs/01_credential-leakage.md)
- [課題2: 特権コンテナ脱出](docs/02_privileged-container.md)
- [課題3: IAM過剰権限 + SSRF](docs/03_iam-overperms.md)

---

## 注意事項

- **本教材は学習目的のみを想定しています。** 脆弱な設定を実際のクラウド環境に適用しないでください。
- 演習中は `answers/` ディレクトリを見ずに自力で解決を試みてください。
- LocalStackを使った課題3は、実際のAWSアカウントは不要です。
