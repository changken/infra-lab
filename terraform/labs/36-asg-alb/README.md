# Lab 36: Auto Scaling Group + ALB + Scaling Policy

> 建立 Launch Template，透過 ASG 在 2 個 AZ 自動維持 EC2 數量，並以 ALB 分配 HTTP 流量；Target Tracking Policy 依 CPU 使用率自動擴縮。

**費用等級**：🟡 注意（~$0.30，ALB ~$0.02/hr，EC2 t3.micro × 2 ~$0.02/hr，練完當天 destroy）

---

## 學習目標

- 理解 **Launch Template** 與 **Auto Scaling Group** 的關係（藍圖 vs 執行者）
- 建立跨 2 個 AZ 的 **Application Load Balancer**，並設定 Target Group Health Check
- 掌握 **EC2 Security Group 引用 ALB Security Group**（不暴露 EC2 到 Internet）
- 設定 `health_check_type = "ELB"`，理解它與 `"EC2"` 的差異
- 撰寫 **Target Tracking Scaling Policy**，並理解三種 Scaling Policy 的取捨
- 透過 `user_data` 在 EC2 啟動時自動安裝 HTTP 服務

---

## 架構

```
Internet
    │ port 80
    ▼
┌──────────────────────────────────────────┐
│  ALB (application load balancer)         │
│  SG: allow 80 from 0.0.0.0/0            │
│  Subnets: public-a (AZ-a), public-b (AZ-b)│
└──────────┬───────────────────────────────┘
           │ forward
           ▼
┌──────────────────────────────────────────┐
│  Target Group (HTTP:80, health: GET /)   │
│  ┌───────────────┐ ┌───────────────┐     │
│  │ EC2 (AZ-a)   │ │ EC2 (AZ-b)   │     │
│  │ SG: allow 80 │ │ SG: allow 80 │     │
│  │ from ALB SG  │ │ from ALB SG  │     │
│  └───────────────┘ └───────────────┘     │
└──────────────────────────────────────────┘
           ↑ 自動註冊 / 管理
┌──────────────────────────────────────────┐
│  Auto Scaling Group                      │
│  min=1, max=3, desired=2                 │
│  Launch Template → AL2023, user_data     │
│  health_check_type = "ELB"              │
└──────────────────────────────────────────┘
           ↑ CPU 50% Target Tracking
┌──────────────────────────────────────────┐
│  Scaling Policy (TargetTrackingScaling)  │
│  ASGAverageCPUUtilization → 50%          │
└──────────────────────────────────────────┘
```

---

## 你要做的事

| TODO | 資源 | 關鍵概念 |
|------|------|---------|
| 1 | VPC + 2 Public Subnets + IGW + Route Table | ALB 強制要求 2+ AZ |
| 2 | `aws_security_group.alb` + `aws_security_group.ec2` | EC2 SG 的 ingress 來源用 `security_groups`（不用 CIDR） |
| 3 | `aws_launch_template` | `user_data = base64encode(...)` 自動安裝 HTTP 服務 |
| 4 | `aws_lb_target_group` + `aws_lb` + `aws_lb_listener` | `health_check.matcher = "200"` |
| 5 | `aws_autoscaling_group` | `health_check_type = "ELB"`, `health_check_grace_period = 300` |
| 6 | `aws_autoscaling_policy` | `policy_type = "TargetTrackingScaling"`, `target_value = 50.0` |

---

## 指令

```bash
# 1. 複製變數範例
cp terraform.tfvars.example terraform.tfvars

# 2. 初始化
terraform init

# 3. 格式化（填完所有 TODO 後執行）
terraform fmt

# 4. 語法驗證
terraform validate

# 5. 預覽（確認將建立 15+ 個資源）
terraform plan

# 6. 部署（ALB 啟動需要約 2-3 分鐘）
terraform apply
```

---

## 驗證

### 1. 確認 ALB 狀態為 active

```bash
ALB_ARN=$(terraform output -raw alb_arn)

aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query 'LoadBalancers[0].{State:State.Code,DNSName:DNSName}' \
  --output table
```

**期望輸出**：`State = active`

### 2. 確認 Target Group 有健康的 EC2

```bash
# 等待 EC2 啟動並通過 Health Check（約 2-5 分鐘）
eval "$(terraform output -raw target_group_health_command)"
```

**期望輸出**：2 個 EC2 的 `State = healthy`

### 3. HTTP 請求測試

```bash
# 多次請求，觀察 ALB 分流到不同 EC2
for i in {1..5}; do
  curl -s "$(terraform output -raw alb_dns_name)"
  echo ""
done
```

**期望輸出**：每次回應顯示不同的 Instance ID 或 AZ（Round Robin 分流）

### 4. 確認 ASG 狀態

```bash
eval "$(terraform output -raw asg_status_command)"
```

**期望輸出**：`Min=1, Max=3, Desired=2, Instances=2`

### 5. 確認 Scaling Policy 已建立

```bash
ASG_NAME=$(terraform output -raw asg_name)

aws autoscaling describe-policies \
  --auto-scaling-group-name "$ASG_NAME" \
  --query 'ScalingPolicies[*].{Name:PolicyName,Type:PolicyType,Status:Enabled}' \
  --output table
```

### 6. 手動觸發 Scale Out 測試（選做）

```bash
# 調高 desired_capacity 觀察 ASG 自動啟動第 3 台 EC2
ASG_NAME=$(terraform output -raw asg_name)

aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$ASG_NAME" \
  --desired-capacity 3

# 等待 ~2 分鐘後確認
eval "$(terraform output -raw target_group_health_command)"
```

---

## 結束

```bash
terraform destroy -auto-approve
```

確認輸出包含 `Destroy complete!`。

> **注意**：destroy 前 ALB 可能需要幾秒終止連線，若 destroy 失敗請重試一次。

---

## 成本估算

| 資源 | 費用 |
|------|------|
| ALB（base）| $0.008/hr |
| ALB LCU（lab 流量極低）| < $0.01 |
| EC2 t3.micro × 2 | $0.0104/hr × 2 = ~$0.02/hr |
| VPC / SG / ASG | $0 |
| **合計（2 小時練習）** | **~$0.06（🟡 注意，練完當天 destroy）** |

---

## 核心概念釐清

### health_check_type 比較（面試必考）

| | `"EC2"`（預設）| `"ELB"` |
|--|--------------|---------|
| 檢查對象 | VM 是否存活（hypervisor 層）| HTTP 回應是否 200（應用層）|
| 情境 | VM 開著但 httpd 掛了 | VM 開著且 httpd 正常回應 |
| ASG 判斷 | ✅ 健康（VM 存活）| ❌ 不健康（HTTP 失敗），自動替換 |
| 建議 | 不推薦（不準確）| **推薦**（確保應用層健康）|

### 三種 Scaling Policy 比較

| 策略 | 設定複雜度 | 行為 | 適用場景 |
|------|-----------|------|---------|
| Simple Scaling | 低 | 觸發 Alarm 後固定加/減 N 台，等 cooldown | 流量模式簡單 |
| Step Scaling | 中 | 根據 Alarm 超出幅度分段調整台數 | 需要精細控制 |
| **Target Tracking** | 低 | 設目標值，AWS 自動計算調整幅度 | **推薦，大多數場景** |

### Launch Template vs Launch Configuration

| | Launch Template（推薦）| Launch Configuration（舊版）|
|--|----------------------|--------------------------|
| 版本管理 | ✅ 支援版本，可回滾 | ❌ 不支援版本 |
| 新功能支援 | ✅ 持續新增 | ❌ 已停止新增功能 |
| 混合 Spot/On-Demand | ✅ 支援 | ❌ 不支援 |
| AWS 建議 | **優先使用** | 僅維護舊架構 |

---

## 卡關提示

| 症狀 | 原因 |
|------|------|
| `apply` 失敗：`InvalidSubnet` / `at least 2 subnets in 2 different AZ` | ALB subnets 只指定了一個 AZ，需要至少 2 個不同 AZ |
| Target Group 一直顯示 `unhealthy` | user_data 尚未完成（等 2-3 分鐘）；或 EC2 SG 沒允許 ALB SG 的流量 |
| EC2 被 ASG 不斷終止再啟動 | `health_check_grace_period` 太短，EC2 還在跑 user_data 就被判定為 unhealthy |
| curl 回應 502 Bad Gateway | EC2 的 httpd 尚未啟動；或 Target Group 沒有 healthy 的 EC2 |
| curl 每次結果都是同一台 EC2 | 正常，ALB 對同一 client IP 可能做 session persistence；改用不同 IP 測試 |
| `destroy` 卡住很久 | ALB 刪除需要約 1-2 分鐘，正常現象，等待即可 |
| Scaling Policy 建立後 CPU 沒有變化 | Target Tracking 的 Scale In 有 15 分鐘 cooldown，Scale Out 沒有 |
