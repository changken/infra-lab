# Lab 12: EKS Cluster Basic

建立一個基礎的 EKS 集群。
**⚠️ 本專案最耗時且有固定成本的 Lab — 務必預留 1 小時以上並在結束後立刻銷毀。**

## 學習目標

- `aws_eks_cluster`: EKS 控制平面
- `aws_eks_node_group`: 受管節點群組
- IAM Roles: 了解 Cluster Role 和 Node Role 的區別
- VPC 配置: EKS 對子網標籤的特殊需求

## 預估成本
- EKS Control Plane: $0.10/小時
- EC2 Nodes (t3.medium x2): 約 $0.08/小時
- **總計約 $0.20/小時**。

## 快速開始

1. 準備 VPC（可沿用 Lab 02 或使用 Data Source 引用）
2. `terraform init`
3. `terraform apply` (約需 15-20 分鐘)
4. 測試連線: `aws eks update-kubeconfig --name <cluster_name>`
5. **立刻清理**: `terraform destroy`

## 注意事項
- EKS 建立與刪除都非常慢，請耐心等待。
- 務必確認 `terraform destroy` 完全成功，手動去 Console 檢查有無殘留的 ELB 或 Volume。
