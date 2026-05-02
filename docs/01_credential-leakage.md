# 課題1: クレデンシャル漏洩疑惑（App層）

**難易度:** ★☆☆  
**対象ファイル:** `app/config.js`, `k8s/overlays/dev/deployment-patch.yaml`

---

## シナリオ

開発チームから「DBへの不正アクセスの痕跡がある」と報告が入りました。  
調査を進めると、本番DBのパスワードが未知のIPアドレスから試行されていたことが判明しました。  
アプリケーションのソースコードや設定ファイルに、認証情報がどのように管理されているか確認してください。

---

## 攻撃シナリオ

```
攻撃者
  │
  ├─ [1] GitHubリポジトリの検索
  │       → config.js に DB_PASSWORD = "super_secret_password_123" を発見
  │
  ├─ [2] Kubernetes マニフェストの確認
  │       → deployment-patch.yaml の env に平文パスワードを発見
  │
  └─ [3] /debug/config エンドポイントへのアクセス
          → HTTPレスポンスでAWSアクセスキーを入手
```

---

## 調査手順

### Step 1: ソースコードの確認

```bash
# ハードコードされたクレデンシャルを探す
grep -r "password\|secret\|key\|token" app/ --include="*.js" -i
```

**確認ポイント:**
- `app/config.js` の `password` フィールドのデフォルト値を見てください
- AWSのアクセスキーが直接書かれていませんか？

### Step 2: Kubernetesマニフェストの確認

```bash
# 稼働中のPodの環境変数を確認
kubectl get pod -l app=backend -n dojo -o yaml | grep -A2 "env:"

# デプロイ中の実際の設定を確認
kubectl exec -n dojo deploy/backend -- env | grep -E "DB_|AWS_"
```

**確認ポイント:**
- `k8s/overlays/dev/deployment-patch.yaml` の `env` セクションを確認する
- ConfigMapとSecretのどちらを使っていますか？

### Step 3: デバッグエンドポイントの確認

```bash
# ⚠️ このエンドポイントは何を返しますか？
curl http://localhost:8080/debug/config
```

---

## 問題の整理

| 問題 | 場所 | リスク |
|------|------|--------|
| DBパスワードのハードコード | `app/config.js:8` | Gitログに永続的に残る |
| AWSキーのハードコード | `app/config.js:14-15` | 公開リポジトリで即座に悪用される |
| マニフェストへの平文記述 | `deployment-patch.yaml:env` | `kubectl get`で誰でも参照可能 |
| デバッグエンドポイントの露出 | `app/index.js:/debug/config` | 認証なしでクレデンシャルを返す |

---

## 修正方針

### レベル1: K8s Secret を使う

```yaml
# 1. Secretを作成
kubectl create secret generic db-credentials \
  --from-literal=password='実際のパスワード' \
  -n dojo

# 2. deployment.yamlでsecretKeyRefを使って参照
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-credentials
        key: password
```

### レベル2: AWS Secrets Manager + External Secrets Operator（推奨）

```bash
# ESO（External Secrets Operator）のインストール
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```

```yaml
# ExternalSecretリソースで自動同期
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: dojo
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secretsmanager
    kind: SecretStore
  target:
    name: db-credentials
  data:
    - secretKey: password
      remoteRef:
        key: dojo/backend/db
        property: password
```

### デバッグエンドポイントの削除

```javascript
// app/index.js から以下を削除
// app.get("/debug/config", ...) を本番環境では無効化するか完全削除
```

---

## 解答例

`answers/k8s/secret.yaml` と `answers/k8s/deployment-fixed.yaml` を参照してください。

---

## 学習のまとめ

- **シークレットは絶対にコードにハードコードしない**（`.gitignore` に頼るだけでは不十分）
- K8s Secretは`base64`エンコードされているだけで暗号化ではない。Sealed Secretsや ESOを使うこと
- GitHubのシークレットスキャン機能（Push Protection）を有効化すること
- `git log` や `git blame` でコミット履歴に残ったクレデンシャルは**ローテーション必須**
