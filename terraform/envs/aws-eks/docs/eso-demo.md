# External Secrets Operator (ESO) Demo — AWS Secrets Manager 整合

## 架構概覽

```
Secrets Manager (infra-lab-dev/custom-app)
   │
   │  GetSecretValue（IRSA）
   ▼
ESO Controller（external-secrets namespace）
   │  IRSA: infra-lab-dev-eso-role
   │
   │  建立 / 同步（refreshInterval: 1h）
   ▼
ClusterSecretStore (aws-secrets-manager)
   │
   ▼
ExternalSecret (custom-app-secrets, namespace: custom-app)
   │
   ▼
K8s Secret (custom-app-secrets)
   │  key: chat-api-key
   ▼
Pod (custom-app) → env.CHAT_API_KEY
```

**核心優勢**：K8s Secret 不再手動建立，也不出現在 Git history 中。值的更新只需改 Secrets Manager，ESO 自動同步。

---

## 元件清單

| 元件 | 位置 | 說明 |
|------|------|------|
| `eso.tf` | infra-lab Terraform | Secrets Manager secret + ESO IRSA role |
| ESO Helm chart | external-secrets namespace | controller + webhook + cert-controller |
| `k8s/eso/cluster-secret-store.yaml` | infra-lab | ClusterSecretStore（全叢集共用） |
| `k8s/external-secret.yaml` | eks-app repo | ExternalSecret（由 ArgoCD 部署） |

---

## Terraform 資源（eso.tf）

### Secrets Manager Secret
```hcl
resource "aws_secretsmanager_secret" "custom_app" {
  name                    = "infra-lab-dev/custom-app"
  recovery_window_in_days = 0   # Lab 環境：允許立刻刪除
}

resource "aws_secretsmanager_secret_version" "custom_app" {
  secret_string = jsonencode({ chat-api-key = "..." })
  lifecycle {
    ignore_changes = [secret_string]   # 避免覆蓋 console 手動更新的值
  }
}
```

### ESO IRSA Policy（最小權限）
```hcl
Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
Resource = aws_secretsmanager_secret.custom_app.arn   # 只允許此 secret
```

### OIDC sub condition
```
system:serviceaccount:external-secrets:external-secrets
```
ESO controller 的 SA 才能 assume role，其他 SA 無法。

---

## ESO Helm 安裝

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=\
arn:aws:iam::661515655645:role/infra-lab-dev-eso-role
```

安裝後的 Pods：
```
external-secrets-xxx          # 主 controller（同步 secret）
external-secrets-cert-controller-xxx   # TLS cert 管理
external-secrets-webhook-xxx  # admission webhook（驗證 CR）
```

---

## ClusterSecretStore

```yaml
# k8s/eso/cluster-secret-store.yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      # ESO controller SA 已有 IRSA annotation，此處無需額外 auth
```

確認狀態：
```bash
kubectl get clustersecretstore aws-secrets-manager
# NAME                  STATUS   CAPABILITIES   READY
# aws-secrets-manager   Valid    ReadWrite      True
```

---

## ExternalSecret（eks-app GitOps）

```yaml
# k8s/external-secret.yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: custom-app-secrets
  namespace: custom-app
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: custom-app-secrets   # 建立的 K8s Secret 名稱
    creationPolicy: Owner      # ESO 負責 lifecycle
  data:
    - secretKey: chat-api-key
      remoteRef:
        key: infra-lab-dev/custom-app   # Secrets Manager secret name
        property: chat-api-key          # JSON 欄位
```

---

## 驗證結果

```bash
# ExternalSecret 狀態
kubectl get externalsecret -n custom-app
# NAME                 STORE                 STATUS         READY   LAST SYNC
# custom-app-secrets   aws-secrets-manager   SecretSynced   True    15s

# K8s Secret 內容（由 ESO 自動建立）
kubectl get secret custom-app-secrets -n custom-app \
  -o jsonpath='{.data.chat-api-key}' | base64 -d
# demo-lab-key-9f5d36bc5a62449d

# ArgoCD 狀態
kubectl get application custom-app -n argocd
# NAME         SYNC STATUS   HEALTH STATUS
# custom-app   Synced        Healthy
```

---

## 更新 Secret 的流程

不需要 `kubectl` 或 `git push`，只需：

```bash
# 方法 1：AWS CLI
aws secretsmanager put-secret-value \
  --secret-id infra-lab-dev/custom-app \
  --secret-string '{"chat-api-key":"new-key-here"}'

# 方法 2：Console → Secrets Manager → infra-lab-dev/custom-app → Edit
```

ESO 在下個 `refreshInterval`（1h）自動同步到 K8s Secret。若要立即生效：
```bash
kubectl annotate externalsecret custom-app-secrets -n custom-app \
  force-sync=$(date +%s) --overwrite
```

---

## SecretStore vs ClusterSecretStore

| | SecretStore | ClusterSecretStore |
|--|-------------|-------------------|
| 範圍 | 單一 namespace | 全叢集 |
| 適用場景 | 各 app 自己管 | 集中管理（本 Lab 採用） |
| IRSA 設定 | 每個 namespace 各自的 SA | ESO controller SA 統一 |

---

## 延伸閱讀

- [irsa-demo.md](./irsa-demo.md) — Pod 層級的 IRSA（本 Lab 的 ESO 也用同樣機制）
- [gitops-cicd-demo.md](./gitops-cicd-demo.md) — GitOps pipeline（ExternalSecret 透過 ArgoCD 部署）
- ESO 官方文件：https://external-secrets.io/latest/provider/aws-secrets-manager/
