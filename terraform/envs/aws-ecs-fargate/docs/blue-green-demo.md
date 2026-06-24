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

```go
// app/main.go：改一下 version，模擬有新版本
APP_VERSION = "2.0.0"  // 在 terraform.tfvars 改 app_version
```

或直接在 `terraform.tfvars` 改：
```hcl
app_version = "2.0.0"
```

### 步驟 2：Build & Push 新 image

```bash
ECR=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR

# 打新 tag 方便區分
docker build -t $ECR:v2 ./app
docker push $ECR:v2
```

### 步驟 3：註冊新 Task Definition

```bash
# 取得現有 task definition，換 image tag
CURRENT_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition infra-lab-dev-app \
  --query 'taskDefinition' --output json)

NEW_TASK_DEF=$(echo "$CURRENT_TASK_DEF" | jq \
  --arg IMAGE "$ECR:v2" \
  '.containerDefinitions[0].image = $IMAGE |
   del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
       .compatibilities, .registeredAt, .registeredBy)')

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK_DEF" \
  --query 'taskDefinition.taskDefinitionArn' --output text)

echo "New Task Definition: $NEW_TASK_DEF_ARN"
```

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

## 搭配 CloudWatch Alarm 自動回滾

```hcl
# 在 codedeploy.tf 加入 alarm_configuration
alarm_configuration {
  alarms  = ["infra-lab-dev-5xx-rate"]  # CloudWatch Alarm 名稱
  enabled = true
}
```

當 5xx 錯誤率超標，CodeDeploy 自動停止部署並回滾，類比 Argo Rollouts 的 AnalysisTemplate。
