# A-04：AKS Workload Identity 🔴 接續 A-03

> Pod 免憑證存取 Azure Key Vault，對比 EKS IRSA（lab 17）。
> **前置條件**：A-03 AKS cluster 必須已 apply 且 running。

**費用估算**：Key Vault standard ≈ $0.03/10K 操作（幾乎免費）；AKS node 費用在 A-03 計算。

---

## 學習目標

- 理解 Azure Workload Identity vs AWS IRSA 的架構差異
- 學會 `azurerm_federated_identity_credential`（對比 IRSA Trust Policy）
- 實作 Pod 透過 ServiceAccount 取得 Azure token，讀取 Key Vault secret
- 體驗 `enable_rbac_authorization = true` 的 Key Vault RBAC 模式

## AWS vs Azure 對比

| 元素 | AWS IRSA (Lab 17) | Azure Workload Identity (本 Lab) |
|------|------------------|----------------------------------|
| 角色/身份 | IAM Role | User Assigned Managed Identity |
| OIDC 設定 | `aws_iam_openid_connect_provider`（手動建） | A-03 的 `oidc_issuer_enabled = true`（已建好） |
| 信任關係 | IAM Role Trust Policy（JSON） | `azurerm_federated_identity_credential`（獨立資源） |
| Subject | `system:serviceaccount:ns:sa` | `system:serviceaccount:ns:sa`（相同！） |
| SA annotation | `eks.amazonaws.com/role-arn` | `azure.workload.identity/client-id` |
| Pod label | 無需額外 label | `azure.workload.identity/use: "true"` |
| 目標服務 | Secrets Manager | Key Vault |
| 存取控制 | IAM Policy | RBAC Role Assignment |

## 架構

```
Pod（label: azure.workload.identity/use=true）
 │  使用 ServiceAccount（annotation: client-id）
 │
 ▼ OIDC Token 換 Azure Token
Azure AD
 │
 ▼ 驗證 Federated Credential（issuer + subject 符合）
User Assigned Managed Identity
 │  Key Vault Secrets User Role
 ▼
Azure Key Vault → 讀取 demo-secret
```

## 你要做的事

| TODO | 資源 | 對比 AWS |
|------|------|---------|
| TODO 1 | `azurerm_resource_group` | — |
| TODO 2 | `azurerm_user_assigned_identity` | IAM Role |
| TODO 3 | `azurerm_federated_identity_credential` | IAM Trust Policy OIDC condition |
| TODO 4 | `azurerm_key_vault` | Secrets Manager |
| TODO 5 | `azurerm_key_vault_secret` | aws_secretsmanager_secret_version |
| TODO 6 | `azurerm_role_assignment` terraform_kv_admin | Terraform 自己寫入 secret 的權限 |
| TODO 7 | `azurerm_role_assignment` workload_kv_read | Pod 讀取 secret 的權限 |
| outputs | `identity_client_id`、`key_vault_uri` | — |

## 操作步驟

```bash
# 前置：確認 A-03 的 AKS 還在跑
cd ../A-03-aks-cluster
az aks show --name $(terraform output -raw cluster_name) \
            --resource-group $(terraform output -raw resource_group_name) \
            --query provisioningState -o tsv   # 應顯示 Succeeded

# 取得 A-03 output，填入本 lab 的 terraform.tfvars
terraform output -raw oidc_issuer_url
terraform output -raw cluster_name
terraform output -raw resource_group_name

# 部署本 lab
cd ../A-04-aks-workload-identity
cp terraform.tfvars.example terraform.tfvars
# 填入上方取得的值

terraform init
terraform fmt && terraform validate
terraform apply
```

## 驗證

```bash
# 1. 確認連上 A-03 的 AKS
az aks get-credentials \
  --resource-group <aks_resource_group_name> \
  --name <aks_cluster_name>

# 2. 建立 ServiceAccount（填入 identity_client_id）
terraform output service_account_manifest
# 複製輸出，把 <填入 identity_client_id output> 換成實際值，存成 sa.yaml
kubectl apply -f sa.yaml

# 3. 建立測試 Pod
terraform output test_pod_manifest > test-pod.yaml
kubectl apply -f test-pod.yaml
kubectl wait --for=condition=Ready pod/wi-test --timeout=60s

# 4. 進入 Pod
kubectl exec -it wi-test -- bash

# ── 以下在 Pod 內執行 ─────────────────────────────────────────
# Workload Identity 會自動注入三個環境變數：
#   AZURE_CLIENT_ID            ← User Assigned Identity 的 client_id
#   AZURE_TENANT_ID            ← Azure AD tenant
#   AZURE_FEDERATED_TOKEN_FILE ← OIDC token 檔案路徑（/var/run/secrets/azure/tokens/...）

# 確認環境變數有注入（若都是空的，代表 SA annotation 或 Pod label 有問題）
env | grep AZURE_

# 5. 用 Federated Token 登入（不能用互動式 az login，要這樣）
az login --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
  --service-principal \
  -u $AZURE_CLIENT_ID \
  --tenant $AZURE_TENANT_ID

# 6. 讀取 Key Vault secret
az keyvault secret show \
  --vault-name <key_vault_name> \
  --name demo-secret \
  --query value -o tsv
# 應顯示：hello-from-keyvault
# ─────────────────────────────────────────────────────────────

# 離開 Pod
exit

# 清理
kubectl delete pod wi-test
kubectl delete serviceaccount workload-identity-sa
```

> **為什麼不能直接 `az keyvault secret show`？**
> `az` CLI 在 Pod 內預設沒有登入狀態，Workload Identity 注入的是 OIDC token 檔案（`$AZURE_FEDERATED_TOKEN_FILE`），
> 不是 `az login` 的 session。必須用 `--federated-token` 先換取 Azure AD token，`az` 才知道用哪個身份。
> 這和 AWS IRSA 不同——IRSA 會自動注入 `AWS_WEB_IDENTITY_TOKEN_FILE`，AWS SDK 會自動讀取，不需要手動換 token。

## 清除資源

```bash
terraform destroy -auto-approve
# 別忘了也 destroy A-03：cd ../A-03-aks-cluster && terraform destroy -auto-approve
```

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `federated_identity_credential` subject 錯誤 | 格式必須是 `system:serviceaccount:<ns>:<sa-name>`，大小寫敏感 |
| Pod 拿不到 token | SA 的 annotation `client-id` 填錯，或 Pod 缺少 label `azure.workload.identity/use: "true"` |
| Key Vault secret 寫入失敗 | TODO 6 的 `terraform_kv_admin` role assignment 沒建，或 `depends_on` 缺少 |
| `az keyvault secret show` 401 / login required | Pod 內需先執行 `az login --federated-token`，不能直接呼叫 CLI |
| `az keyvault secret show` 403 | TODO 7 的 `workload_kv_read` role assignment 的 `principal_id` 填錯 |
| `AZURE_FEDERATED_TOKEN_FILE` 是空的 | Pod label `azure.workload.identity/use: "true"` 缺少，或 AKS 未啟用 `workload_identity_enabled` |
| Key Vault 名稱衝突 | 全域唯一，在 project 名稱加個隨機數字 |
