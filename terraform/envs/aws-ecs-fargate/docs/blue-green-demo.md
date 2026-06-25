# Blue/Green Deployment Demo（CodeDeploy）

## 架構回顧

```
Internet
  │
  ├── :80  → Production Listener → [Blue TG | Green TG]  ← CodeDeploy 切換
  └── :8080 → Test Listener     → [Green TG]             ← 部署期間預覽

ECS Service（deployment_controller = CODE_DEPLOY）
  └── CodeDeploy Deployment Group
        ├── Blue TG（當前生產）
        └── Green TG（新版本）
```

## 對比 Argo Rollouts（EKS）

| 概念 | Argo Rollouts | CodeDeploy |
|------|--------------|------------|
| 部署描述 | Rollout YAML（CRD）| AppSpec JSON |
| 流量控制 | Istio / ALB / NGINX | ALB（原生整合）|
| 策略 | Canary weight % | Canary / Linear / AllAtOnce |
| 驗證 | AnalysisTemplate（Prometheus）| CloudWatch Alarms |
| 安裝 | Helm chart + operator | 零安裝（AWS 托管）|
| 回滾 | 手動或 AnalysisTemplate 失敗 | auto_rollback_configuration |

## 部署流程步驟

### 步驟 1：修改 app（模擬新版本）

app 程式碼位於獨立 repo [changken/ecs-app](https://github.com/changken/ecs-app)。

```bash
# clone app repo（第一次）
git clone https://github.com/changken/ecs-app.git
cd ecs-app

# 改任何東西，例如在 main.go 加個 endpoint 或改回傳內容
```

### 步驟 2 & 3：Build、Push、註冊 Task Definition（自動）

push 到 `main` 後，GitHub Actions 自動完成：
- `docker build` → ECR push（`:$SHA` + `:latest`）
- `aws ecs register-task-definition`（只換 image，其他設定不動）

> 手動操作請參考 [ecs-app README](https://github.com/changken/ecs-app#cicd-流程)。

### 步驟 4：觸發 CodeDeploy 部署

```bash
APP=$(terraform output -raw codedeploy_app_name)
DG=$(terraform output -raw codedeploy_deployment_group)
PORT=$(terraform output -raw container_port 2>/dev/null || echo "8080")

DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name $APP \
  --deployment-group-name $DG \
  --revision '{
    "revisionType": "AppSpecContent",
    "appSpecContent": {
      "content": "{\"version\":0.0,\"Resources\":[{\"TargetService\":{\"Type\":\"AWS::ECS::Service\",\"Properties\":{\"TaskDefinition\":\"'"$NEW_TASK_DEF_ARN"'\",\"LoadBalancerInfo\":{\"ContainerName\":\"app\",\"ContainerPort\":8080}}}}]}"
    }
  }' \
  --query 'deploymentId' --output text)

echo "Deployment ID: $DEPLOYMENT_ID"
```

### 步驟 5：觀察部署過程

```bash
# 監看部署狀態
watch -n 5 "aws deploy get-deployment \
  --deployment-id $DEPLOYMENT_ID \
  --query 'deploymentInfo.{Status:status,Overview:deploymentOverview}'"

# 或用 AWS CLI 等待完成
aws deploy wait deployment-successful --deployment-id $DEPLOYMENT_ID
```

### 步驟 6：部署期間用 Test Listener 預覽新版本

```bash
TEST_URL=$(terraform output -raw alb_test_url)
PROD_URL=$(terraform output -raw alb_dns_name)

# Green TG（新版本）：透過 :8080 存取
curl -s $TEST_URL | jq .version
# 預期："2.0.0"

# Blue TG（舊版本）：仍在 :80
curl -s $PROD_URL | jq .version
# 預期："1.0.0"（尚未切換）
```

### 步驟 7：確認流量切換完成

```bash
# 部署完成後，:80 也應該是新版本
curl -s $PROD_URL | jq .version
# 預期："2.0.0"（切換完成）
```

## 手動 Approve 模式（類比 Argo Rollouts canary pause）

預設 `action_on_timeout = "CONTINUE_DEPLOYMENT"` 是全自動切換。
改成需要人工確認：

在 `codedeploy.tf` 修改：
```hcl
deployment_ready_option {
  action_on_timeout    = "STOP_DEPLOYMENT"
  wait_time_in_minutes = 60  # 等 60 分鐘，期間可測試 :8080
}
```

然後部署期間手動 approve：
```bash
# 查看等待 approve 的 deployment
aws deploy list-deployments \
  --application-name $APP \
  --deployment-group-name $DG \
  --include-only-statuses Ready

# 手動 continue（切換流量）
aws deploy continue-deployment \
  --deployment-id $DEPLOYMENT_ID \
  --deployment-wait-type READY_WAIT
```

## 回滾

```bash
# 手動停止並回滾（CodeDeploy 把 Blue TG 改回 Production Listener）
aws deploy stop-deployment \
  --deployment-id $DEPLOYMENT_ID \
  --auto-rollback-enabled

# 或等 auto_rollback_configuration 自動觸發（deployment failure 時）
```

## 流量切換策略對比

| 策略 | 說明 | 適合場景 |
|------|------|---------|
| `ECSAllAtOnce` | 一次全切（預設）| 快速驗證、lab 練習 |
| `ECSCanary10Percent5Minutes` | 10% 跑 5 分鐘，再全切 | 生產，降低爆炸半徑 |
| `ECSCanary10Percent15Minutes` | 10% 跑 15 分鐘 | 生產，更長觀察期 |
| `ECSLinear10PercentEvery1Minutes` | 每分鐘加 10% | 需要漸進式切換 |
| `ECSLinear10PercentEvery3Minutes` | 每 3 分鐘加 10% | 需要更慢的漸進切換 |

在 `terraform.tfvars` 改 `codedeploy_config` 即可切換策略：
```hcl
codedeploy_config = "CodeDeployDefault.ECSCanary10Percent5Minutes"
```

套用後 terraform apply：
```bash
terraform apply -target=aws_codedeploy_deployment_group.app
```

## Canary 流量觀察

Canary 策略下，ALB 會用 **weighted target group** 把流量按比例分給 Blue/Green TG。
`ECSCanary10Percent5Minutes` = 前 5 分鐘 10% 打新版，之後一次全切。

**觀察時機**：Green task 從啟動到 health check 通過約需 30-60 秒，
這段時間就在消耗 canary window。建議用較長的策略或在部署觸發後立即開始採樣。

### 推薦觀察指令（PowerShell）

```powershell
# 部署觸發後立即執行，持續採樣
$ALB = "http://<alb-dns>"
1..200 | ForEach-Object {
    $r = try { Invoke-RestMethod "$ALB/version" -TimeoutSec 2 } catch { $null }
    [PSCustomObject]@{ deploy = $r.deploy ?? "[old]"; git = $r.git_commit }
    Start-Sleep -Milliseconds 500
} | Group-Object deploy | Select-Object Name, Count
```

**預期輸出（canary 期間）**：
```
Name         Count
----         -----
[old]          170   # ~85% 舊版（Blue TG）
canary-test     30   # ~15% 新版（Green TG）
```

> Green task 起來前的 503 會被 catch 忽略，不影響統計。

### 各策略 window 長度建議

| 策略 | Canary Window | 適合觀察時間 |
|------|--------------|-------------|
| `ECSCanary10Percent5Minutes` | 5 分鐘 | task 啟動後剩 ~4 分鐘可採樣 |
| `ECSCanary10Percent15Minutes` | 15 分鐘 | **推薦 lab 練習**，足夠觀察 |
| `ECSLinear10PercentEvery1Minutes` | 10 分鐘（漸進）| 可看到比例從 10% 爬升至 100% |

## Troubleshooting

### CodeDeploy 部署立即失敗：INVALID_ECS_SERVICE

```
"code": "INVALID_ECS_SERVICE",
"message": "The target ECS service must be configured using one of those two target groups."
```

**原因**：ECS service 的 PRIMARY task set 指向的 TG 不是 blue 或 green（通常是切換 `deployment_controller` 時的舊 TG 殘留）。

**修復**：
```bash
terraform apply -replace=aws_ecs_service.app
```

詳細診斷步驟請參閱 [cleanup.md](./cleanup.md#切換到-code_deploy-後-task-起不來invalid_ecs_service)。

---

### 503 Bad Gateway（ALB 返回）

**診斷**：
```bash
aws ecs describe-services \
  --cluster infra-lab-dev-cluster \
  --services infra-lab-dev-app-service \
  --query 'services[0].{Running:runningCount,Events:events[:3]}' \
  --output json
```

常見原因：
- task 啟動失敗（image pull error → 確認 ECR image 存在且 task execution role 有 ECR 權限）
- health check 未通過（確認 `/health` path 正確，container port 與 TG port 一致）
- SG 沒開 ALB → task 的 port（確認 `aws_security_group.ecs_tasks` ingress 規則）

---

### CodeDeploy 部署卡在 BeforeInstall / Install

```bash
# 查看詳細 lifecycle event log
aws deploy get-deployment \
  --deployment-id $DEPLOYMENT_ID \
  --query 'deploymentInfo.deploymentStatusMessages' \
  --output text
```

通常是新 task set 的 task 啟動失敗，參考 CloudWatch Logs：
```bash
aws logs tail /ecs/infra-lab-dev-app --follow
```

## 搭配 CloudWatch Alarm 自動回滾

```hcl
# 在 codedeploy.tf 加入 alarm_configuration
alarm_configuration {
  alarms  = ["infra-lab-dev-5xx-rate"]  # CloudWatch Alarm 名稱
  enabled = true
}
```

當 5xx 錯誤率超標，CodeDeploy 自動停止部署並回滾，類比 Argo Rollouts 的 AnalysisTemplate。
