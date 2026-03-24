# 使用 Terraform 部署 EC2 網頁伺服器

此 Terraform 組態在 AWS 上部署了一個簡單的 EC2 網頁伺服器 (Apache)。它展示了基礎的基礎設施即程式碼 (IaC) 模式，包括：

*   **EC2 實例**：啟動一個 Amazon Linux 2 實例。
*   **安全組 (Security Group)**：配置 SSH (22) 和 HTTP (80) 的防火牆規則。
*   **SSH 金鑰對**：產生一個新的 SSH 金鑰對以進行安全存取。
*   **使用者數據 (User Data)**：自動安裝並啟動 Apache 網頁伺服器 (`httpd`)。
*   **本地檔案**：將產生的私鑰儲存在本地，以便輕鬆連線。

## 前置作業

*   **Terraform**: v1.2+
*   **AWS CLI**: 已配置適當的憑證。
*   **AWS 帳號**: 具有建立 EC2 實例、安全組和金鑰對的權限。

## 檔案結構

*   `main.tf`: 定義主要資源（EC2、安全組、金鑰對）。
*   `variables.tf`: 輸入變數定義。
*   `outputs.tf`: 輸出值（IP 地址、連線字串）。
*   `locals.tf`: 用於通用標籤 (tags) 的本地變數。
*   `terraform.tf`: Provider 配置和版本設定。
*   `terraform.tfvars.example`: 輸入變數的範本檔案。

## 使用方法

### 1. 初始化

初始化 Terraform 工作目錄以編譯必要的 Provider。

```bash
terraform init
```

### 2. 配置

建立 `terraform.tfvars` 檔案來自定義您的部署。您可以複製提供的範本：

```bash
cp terraform.tfvars.example terraform.tfvars
```

**重要提示：** 編輯 `terraform.tfvars` 並更新 `allowed_ssh_cidr` 為您的公開 IP 地址，以限制 SSH 存取。

```hcl
# terraform.tfvars
allowed_ssh_cidr = "您的.IP.地址.在此/32"
```

### 3. 部署

預覽變更：

```bash
terraform plan
```

執行部署：

```bash
terraform apply
```

### 4. 連線至伺服器

部署成功後，Terraform 會輸出連線指令。您可以直接使用它：

```bash
# 指令會顯示在輸出 (outputs) 中，例如：
ssh -i my-ec2-key.pem ec2-user@<公開_IP>
```

在瀏覽器中開啟 `instance_public_dns` 或 `instance_public_ip` 來檢查網頁伺服器。

### 5. 清理資源

若要刪除此組態建立的所有資源：

```bash
terraform destroy
```

## 輸入變數 (Inputs)

| 名稱 | 描述 | 類型 | 預設值 |
|------|-------------|------|---------|
| `environment` | 環境名稱 (例如：dev, prod) | `string` | `"dev"` |
| `project` | 用於標籤的專案名稱 | `string` | `"terraform-web-server"` |
| `instance_type` | EC2 實例類型 | `string` | `"t3.micro"` |
| `root_volume_size` | 根磁碟區大小 (GB) | `number` | `20` |
| `availability_zone` | 部署的可用區域 | `string` | `"us-east-1a"` |
| `allowed_ssh_cidr` | 允許 SSH 存取的 CIDR 區塊 | `string` | `"118.150.143.171/32"` |
| `key_name` | SSH 金鑰對的名稱 | `string` | `"my-ec2-key"` |

## 輸出值 (Outputs)

| 名稱 | 描述 |
|------|-------------|
| `instance_id` | EC2 實例的 ID |
| `instance_public_ip` | 公開 IP 地址 |
| `instance_public_dns` | 公開 DNS 名稱 |
| `private_key_path` | 產生的私鑰檔案路徑 |
| `ssh_connection_command` | 即裝即用的 SSH 連線字串 |
| `security_group_id` | 建立的安全組 ID |

## 建立的資源

*   `aws_instance.my_instance`: 網頁伺服器實例。
*   `aws_security_group.web_sg`: 允許 SSH 和 HTTP 的安全組。
*   `aws_key_pair.ec2_keypair`: 匯入至 AWS 的 SSH 金鑰對。
*   `tls_private_key.ec2_key`: 產生 RSA 金鑰。
*   `local_file.private_key`: 將私鑰儲存為 `.pem` 檔案。
*   `aws_default_subnet.default_az1`: 引用預設子網。
