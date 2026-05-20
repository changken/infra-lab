# Lab 03: S3 Static Website

用 S3 架靜態網站。**比想像中麻煩**——因為 AWS 從 2023 起預設擋住所有 public access，要正確「開洞」需要 4 個布林值 + 1 個 bucket policy 都對才行。

## 學習目標

- S3 Bucket 的建立與全球唯一命名
- 第一次寫 IAM JSON Policy（用 `jsonencode`）
- 理解 Public Access Block 的 4 個布林值
- Website Configuration（index/error document）
- 用 `aws_s3_object` 上傳檔案 + 用 `etag` 做變更偵測

## 你要做的事

`main.tf` 已經幫你寫好 `random_id`（產生 bucket 後綴），接著完成 6 個 TODO：

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_s3_bucket` | 用 `local.bucket_name` |
| 2 | `aws_s3_bucket_public_access_block` | 4 個布林全部 false（**靜態網站專用**）|
| 3 | `aws_s3_bucket_policy` | 已附 policy JSON，直接 copy |
| 4 | `aws_s3_bucket_website_configuration` | index + error document |
| 5 | `aws_s3_object` (index.html) | 用 `etag = filemd5(...)` |
| 6 | `aws_s3_object` (error.html) | 跟 5 一樣 |

再補完 `outputs.tf` 的 3 個 TODO。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt
terraform validate
terraform plan       # 應該顯示 7 個 to add（含 random_id）
terraform apply
```

### 驗證

```bash
terraform output website_url
```

把 URL 貼進瀏覽器，應該看到 Lab 03 的 hello page。
試著加個 `/anything-not-found`，應該看到 404 error.html。

### 結束（重要）

```bash
terraform destroy -auto-approve
```

⚠️ 如果 bucket 裡有檔案，destroy 會失敗。
但因為我們用 `aws_s3_object` 管檔案，Terraform 會先刪檔再刪 bucket，所以不會卡。

## 成本

**< $1**。流量極低，主要是 storage（兩個 HTML 檔幾 KB）。

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `BucketAlreadyExists` | 罕見（有 random_id），但偶爾真的撞名，再 apply 一次就好 |
| 瀏覽器看到 `AccessDenied` | TODO 2 的 4 個布林沒全部 false，或 TODO 3 的 policy 沒生效 |
| `Error putting S3 policy` | TODO 3 要等 TODO 2 先生效，加 `depends_on` 解決 |
| Endpoint 看到 XML 錯誤頁 | TODO 4 沒做，bucket 還不是 website mode |
| 改 HTML 後 apply 沒重新上傳 | 沒寫 `etag = filemd5(...)`，Terraform 不知道檔案變了 |

## 完成檢查清單

- [ ] `terraform plan` 顯示 **7 個 to add**
  - random_id × 1 + bucket × 1 + public_access_block × 1 + policy × 1 + website_config × 1 + s3_object × 2
- [ ] `terraform apply` 沒有錯誤
- [ ] 瀏覽器看到首頁
- [ ] 瀏覽器訪問不存在的路徑看到 404 error 頁
- [ ] `terraform destroy` 把所有資源清乾淨

## 進階挑戰（選做）

- 改 `index.html` 後再 `apply`，觀察 Terraform plan 顯示什麼
- 嘗試把 `etag` 行刪掉，看會發生什麼
- 故意把 `block_public_policy` 設成 true，看 apply 會怎樣
