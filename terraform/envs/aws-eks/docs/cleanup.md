# Cleanup 指南 — aws-eks Lab 完整清除步驟

## 重要：清除順序

**必須先清 K8s 層，再跑 `terraform destroy`。**

`terraform` 只管它建立的資源。ALB、Security Group 等由 K8s Controller 動態建立的資源，
`terraform destroy` 無法刪除，會造成 VPC 刪除卡住。

---

## Step 1 — 停止 ArgoCD 管理

```bash
kubectl delete application --all -n argocd
```

防止 ArgoCD 在 destroy 期間繼續重建資源。

---

## Step 2 — 刪除所有 Ingress（回收 ALB）

```bash
kubectl delete ingress -A --all
```

確認 ALB 已從 AWS 刪除（約 30-60 秒）：

```bash
aws elbv2 describe-load-balancers --region us-east-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName,`k8s-eks`)].{name:LoadBalancerName,state:State.Code}' \
  --output table
```

⚠️ **常見陷阱**：monitoring（Grafana）和 podinfo 的 ALB 是 ALB Controller 建立的，
不在 terraform state 裡。刪 Ingress 才能讓 Controller 回收它們。

---

## Step 3 — 清除 Karpenter 節點

```bash
kubectl delete nodepool default
kubectl delete ec2nodeclass default
```

等 Karpenter 節點從 EC2 消失（約 1-2 分鐘）：

```bash
kubectl get nodes
```

確認只剩 MNG 的 2 個固定節點即可進行下一步。

---

## Step 4 — 清空 ECR（避免 destroy 報錯）

```bash
aws ecr list-images \
  --repository-name infra-lab-dev-app \
  --region us-east-1 \
  --query 'imageIds[*]' --output json | python3 -c "
import json, sys, subprocess
ids = json.load(sys.stdin)
print(f'Images to delete: {len(ids)}')
for i in range(0, len(ids), 100):
    batch = ids[i:i+100]
    result = subprocess.run([
        'aws', 'ecr', 'batch-delete-image',
        '--repository-name', 'infra-lab-dev-app',
        '--region', 'us-east-1',
        '--image-ids', json.dumps(batch)
    ], capture_output=True, text=True)
    out = json.loads(result.stdout)
    print(f'Deleted: {len(out.get(\"imageIds\",[]))}, Failures: {len(out.get(\"failures\",[]))}')
"
```

---

## Step 5 — terraform destroy

```bash
cd terraform/envs/aws-eks
terraform destroy -auto-approve
```

預計時間：**10-15 分鐘**（EKS control plane 刪除最慢）。

---

## 如果卡住：手動清理殘留資源

### 情況 A：VPC 無法刪除（最常見）

通常是 ALB 遺留的 ENI 或 Security Group 還在。

**查 ENI：**
```bash
VPC_ID=$(aws ec2 describe-vpcs --region us-east-1 \
  --filter "Name=tag:Project,Values=infra-lab" \
  --query 'Vpcs[0].VpcId' --output text)

aws ec2 describe-network-interfaces --region us-east-1 \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].{id:NetworkInterfaceId,desc:Description}' \
  --output table
```

**刪殘留 ALB（ENI 的擁有者）：**
```bash
aws elbv2 describe-load-balancers --region us-east-1 \
  --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
  --output text | xargs -I{} aws elbv2 delete-load-balancer \
  --region us-east-1 --load-balancer-arn {}
```

**刪殘留 Security Group（ALB Controller 建立的）：**
```bash
aws ec2 describe-security-groups --region us-east-1 \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
  --output text | xargs -I{} aws ec2 delete-security-group \
  --region us-east-1 --group-id {}
```

清完後 `terraform destroy` 可繼續完成（或讓已在跑的 process 自動完成）。

### 情況 B：terraform state lock

```
Error: Error acquiring the state lock
```

代表另一個 terraform process 還在跑。等它結束：

```bash
ps aux | grep terraform
# 等 PID 消失後再重試 terraform destroy
```

### 情況 C：destroy 後重跑確認剩餘資源

```bash
terraform state list
```

若還有資源，再跑一次 `terraform destroy -auto-approve`。

---

## 最終確認

```bash
echo "=== EKS ===" && aws eks list-clusters --region us-east-1 --query 'clusters' --output text
echo "=== VPC ===" && aws ec2 describe-vpcs --region us-east-1 --filter "Name=tag:Project,Values=infra-lab" --query 'Vpcs[*].VpcId' --output text
echo "=== EC2 ===" && aws ec2 describe-instances --region us-east-1 --filter "Name=tag:Project,Values=infra-lab" "Name=instance-state-name,Values=running" --query 'Reservations[*].Instances[*].InstanceId' --output text
echo "=== ALB ===" && aws elbv2 describe-load-balancers --region us-east-1 --query 'LoadBalancers[?contains(LoadBalancerName,`k8s-eks`)].LoadBalancerName' --output text
echo "=== terraform state ===" && terraform state list
```

全部空白即清除完成，費用停止計費。

---

## 清除時間記錄（2026-06-24）

| 步驟 | 耗時 |
|------|------|
| ArgoCD / Ingress / Karpenter 清除 | ~2 分鐘 |
| ECR 清空（19 images） | ~10 秒 |
| EKS cluster 刪除 | ~10 分鐘 |
| 手動清 ALB + Security Group | ~5 分鐘 |
| VPC / Subnet / IGW 刪除 | ~5 分鐘 |
| **總計** | **~22 分鐘** |

---

## 可選：刪除 eks-app GitHub repo

若不再需要，到 GitHub → Settings → Delete repository 手動刪除。
Terraform 不管理 GitHub repo，不會自動清除。
