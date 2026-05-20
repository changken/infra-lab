# Lab 02: Custom VPC (Public Only)

把 Lab 01 借用的 default VPC 升級成自建 VPC。
**完全免費**，沒有 NAT Gateway、沒有 EC2，純網路骨架練習。

## 學習目標

- 自己規劃 CIDR 切割（`10.0.0.0/16` → 兩個 `/24`）
- 跨 AZ 部署 public subnet（高可用基礎）
- 設定 Internet Gateway 和 Route Table
- 練習 Terraform 的 `count` 或 `for_each`

## 拓樸

```
    Internet
        │
    ┌───┴───┐
    │  IGW  │
    └───┬───┘
        │
  ┌─────┴──────────────────────────┐
  │   VPC (10.0.0.0/16)            │
  │                                │
  │  ┌──────────────┐ ┌──────────┐ │
  │  │ Subnet A     │ │ Subnet B │ │
  │  │ 10.0.1.0/24  │ │10.0.2.0/24│ │
  │  │ us-east-1a   │ │us-east-1b│ │
  │  └──────────────┘ └──────────┘ │
  │                                │
  │  Route Table: 0.0.0.0/0 → IGW  │
  └────────────────────────────────┘
```

## 你要做的事

打開 `main.tf`，依序完成 5 個 TODO：

| # | Resource | 重點 |
|---|----------|------|
| 1 | `aws_vpc` | CIDR、DNS 設定、tags |
| 2 | `aws_internet_gateway` | 綁到 VPC |
| 3 | `aws_subnet` (×2) | 練 `count` 或 `for_each` |
| 4 | `aws_route_table` | `0.0.0.0/0` → IGW |
| 5 | `aws_route_table_association` | 每個 subnet 綁一筆 |

再補完 `outputs.tf` 的 3 個 TODO output。

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform fmt    # 自動排版
terraform validate
terraform plan
terraform apply
```

### 驗證

1. AWS Console → VPC → Your VPCs，找到 `vpc-lab`
2. 點進去看 Resource Map，應該看到：
   - 1 個 VPC
   - 2 個 public subnet（跨 AZ）
   - 1 個 IGW
   - 1 個 route table，含 `0.0.0.0/0 → igw` 路由

### 結束

```bash
terraform destroy -auto-approve
```

（這個 lab 即使忘記 destroy 也不會花錢，但養成習慣）

## 成本

**$0**。VPC、Subnet、IGW、Route Table 全部免費。

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `plan` 過但 `apply` 失敗 | 90% 是 CIDR 寫錯或 AZ 名稱拼錯 |
| Subnet 跟 AZ 數量對不上 | `count` 用了不一致的 length，檢查 variables |
| Association 報 `subnet_id is required` | 沒用 `[count.index]` 或 `[each.key]` 取出單一 subnet |
| 想看資源關係圖 | `terraform graph | grep aws_` |

## 完成檢查清單

- [ ] `terraform plan` 顯示 **7 個 resource to add**
  - 1 VPC + 1 IGW + 2 subnet + 1 route table + 2 association = 7
- [ ] `terraform apply` 沒有錯誤
- [ ] AWS Console 看得到 VPC Resource Map
- [ ] `terraform output` 印出 4 個值
- [ ] `terraform destroy` 把所有資源清乾淨
