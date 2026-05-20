# Terraform AWS Labs

這是用 Terraform 練習 AWS 基礎設施的專案，採分階段、分服務目錄的方式建立練習。

## 目標

- 建立從基礎到進階的 AWS 學習路徑
- 每個服務可獨立執行與銷毀
- 逐步累積可重用模組

## 前置需求

- Terraform >= 1.2
- AWS CLI 已設定 credentials
- 基本 AWS IAM 權限（EC2、VPC、IAM、S3 等）

## 快速開始

以目前的 EC2 練習為例：

```bash
cd 01-ec2-web-server
terraform init
terraform plan
terraform apply
```

## 目錄結構

```
terraform-aws-labs/
├── 01-ec2-web-server/     # 練習專案
├── modules/               # 可重用模組
│   ├── backend/
│   ├── compute/
│   ├── database/
│   ├── iam-baseline/
│   ├── networking/
│   ├── serverless/
│   └── storage/
├── docs/                  # 文件與學習路線
├── .gitignore
└── README.md
```

## 學習路線圖

完整路線圖請見 `docs/roadmap.md`。

## 學習路徑（精簡版）

1. EC2 / VPC / S3 基礎
2. Serverless（Lambda / API Gateway / DynamoDB）
3. 容器化（ECR / App Runner / ECS Fargate）
4. Kubernetes（EKS）
5. 監控與安全（CloudWatch / Secrets Manager / IAM）

## 注意事項

- `*.tfstate` 含敏感資訊，已加入 `.gitignore`
- 建議正式環境使用 S3 + DynamoDB 作為 remote state
- `.terraform.lock.hcl` 建議提交以鎖定 provider 版本

## 授權

MIT License
