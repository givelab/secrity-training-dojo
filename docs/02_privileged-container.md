# 課題2: 特権コンテナからのホストノード乗っ取り（K8s/EKS層）

**難易度:** ★★☆  
**対象ファイル:** `k8s/overlays/dev/deployment-patch.yaml`

---

## シナリオ

バックエンドAPIのPodに脆弱性があり、攻撃者がコンテナ内でコード実行に成功しました。  
その後、K8sのホストノード（EC2インスタンス）のファイルシステムへのアクセス、さらにはノード全体の乗っ取りが行われている形跡があります。  
なぜコンテナからホスト側にエスケープできたのか、Podの定義を調査してください。

---

## 攻撃シナリオ（コンテナブレイクアウト）

```
攻撃者（コンテナ内にいる状態）
  │
  ├─ [1] privileged: true の確認
  │       → ホストの /dev にアクセス可能
  │
  ├─ [2] hostPath マウントを利用
  │       → ls /host でホストの / ファイルシステムを閲覧
  │       → cat /host/etc/shadow でホストのパスワードハッシュを取得
  │
  ├─ [3] hostPID を悪用
  │       → ps aux でホストの全プロセスを確認
  │       → nsenter --target 1 --mount --uts --ipc --net /bin/bash
  │         → ホストのrootシェルを取得！
  │
  └─ [4] ホストからEC2インスタンスメタデータを取得
          → curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
          → IAMロールの一時クレデンシャルを窃取
```

---

## 調査手順

### Step 1: Podのsecurityコンテキストを確認

```bash
# PodのYAMLを出力して確認
kubectl get pod -l app=backend -n dojo -o yaml

# 特にここに注目:
# spec.hostPID
# spec.hostNetwork
# spec.containers[].securityContext.privileged
# spec.containers[].securityContext.runAsUser
# spec.volumes[].hostPath
```

### Step 2: 実際に侵入してみる（演習）

```bash
# Podにexec
kubectl exec -it -n dojo deploy/backend -- /bin/sh

# コンテナ内で実行
whoami                  # rootで動いているか確認
id

# hostPathマウントでホストのファイルシステムを確認
ls /host/etc/          # ホストの /etc が見える！
cat /host/etc/hostname # ホストのホスト名
```

### Step 3: 特権の範囲を確認

```bash
# コンテナ内で実行
# Capabilitiesを確認（capsh がある場合）
cat /proc/1/status | grep Cap

# デバイスへのアクセスを確認
ls /dev/              # ホストのデバイスが見える
```

---

## 問題の整理

| 設定 | 影響 | リスクレベル |
|------|------|------------|
| `privileged: true` | ホストの全デバイス・権限にアクセス可能 | 🔴 致命的 |
| `hostPID: true` | ホストの全プロセスが見える・操作可能 | 🔴 致命的 |
| `hostNetwork: true` | ホストのネットワーク空間を共有 | 🔴 致命的 |
| `runAsUser: 0` (root) | コンテナ内rootがホスト側に影響 | 🟠 重大 |
| `hostPath: /` | ホストの / を直接マウント | 🔴 致命的 |

---

## 修正方針

### 最小権限のsecurityContextを設定

```yaml
securityContext:
  # ✅ 非rootユーザーで実行
  runAsNonRoot: true
  runAsUser: 1000
  runAsGroup: 1000
  # ✅ 権限昇格を禁止
  allowPrivilegeEscalation: false
  # ✅ Linux Capabilitiesをすべて削除
  capabilities:
    drop:
      - ALL
  # ✅ ルートファイルシステムを読み取り専用に
  readOnlyRootFilesystem: true
```

### hostPath / hostPID / hostNetwork を削除

```yaml
spec:
  # hostPID: true   ← 削除
  # hostNetwork: true ← 削除
  containers:
    - securityContext:
        # privileged: true ← 削除
  volumes:
    # - hostPath: ... ← 削除
```

### Pod Security Admission でクラスタ全体に強制

```bash
# dojo Namespaceにrestrictedプロファイルを適用
kubectl label namespace dojo pod-security.kubernetes.io/enforce=restricted
```

---

## 解答例

`answers/k8s/deployment-fixed.yaml` を参照してください。

---

## 学習のまとめ

- `privileged: true` は「コンテナをホストのrootとして動かす」に等しい
- K8s 1.25以降では **Pod Security Admission (PSA)** がデフォルトで有効
  - `baseline` プロファイル: 最低限の保護（privilegedをブロック）
  - `restricted` プロファイル: ベストプラクティス全適用（本番推奨）
- `runAsNonRoot: true` と `readOnlyRootFilesystem: true` はデフォルトで設定すべき
- `hostPath` が必要な場合は `/tmp` など最小限のパスに限定し、`readOnly: true` を設定
