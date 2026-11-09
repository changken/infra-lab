# O-04：OKE Cluster（Oracle Kubernetes Engine）

> 在 OCI 建立 OKE 叢集並跑工作負載，對標 AWS 的 [Lab 15 EKS](../../labs/15-eks-cluster/)。節點可選 **A1（ARM，Always Free，常缺貨）** 或 **E4（x86，收費但容量充裕）**。
>
> 💰 **成本等級：A1 🟢／E4 🟡**（Basic cluster 的 control plane 免費；A1 在 Always Free 額度內，E4 每天約 US$1.6，見「成本」）
>
> ⏰ **你的 credit 11/22 到期**。練完當天 `terraform destroy`。

## 學習目標

- 理解 OKE 架構：control plane（Oracle 託管）+ node pool（你的 VM）
- 會寫 `oci_containerengine_cluster` 與 `oci_containerengine_node_pool`
- 理解 OCI 網路對 OKE 的需求：API endpoint / worker / LB 三個 subnet 與 Security List
- 會用 data source 查詢相容的 node image（ARM + 對應 K8s 版本）
- 對比 EKS：Basic vs Enhanced cluster、Flannel overlay vs VCN-native CNI
- 用 `kubectl` 連線並部署 workload，驗證 `Service type=LoadBalancer`

## 架構

```
                     你的電腦（allowed_cidr）
                       │ kubectl :6443        │ http :80
                       ▼                      ▼
┌─────────────────── VCN 10.20.0.0/16 ──────────────────────────┐
│                                                                │
│  api subnet 10.20.0.0/28      lb subnet 10.20.20.0/24          │
│  ┌───────────────────────┐    ┌───────────────────────┐        │
│  │ K8s API endpoint      │    │ OCI Load Balancer     │        │
│  │ (Oracle 託管 control  │    │ (Service type=LB 建立)│        │
│  │  plane，免費)         │    └──────────┬────────────┘        │
│  └──────────┬────────────┘               │ NodePort            │
│             │ :10250 / :12250            ▼                     │
│  node subnet 10.20.10.0/24 ───────────────────────────         │
│  ┌──────────────────┐   ┌──────────────────┐                   │
│  │ A1.Flex node #1  │   │ A1.Flex node #2  │  Flannel overlay  │
│  │ 1 OCPU / 6 GB    │   │ 1 OCPU / 6 GB    │  (pod 10.244/16)  │
│  └──────────────────┘   └──────────────────┘                   │
│                         │                                       │
└─────────────────────────┼───────────────────────────────────────┘
                     Internet Gateway
```

## 你要做的事

網路層（VCN / subnet / Security List）**已提供**，你要填的是 OKE 本體：

| TODO | 檔案 | 內容 | 重點 |
|------|------|------|------|
| 1 | `main.tf` | 查 Availability Domain | 用 tenancy 而非 compartment |
| 2 | `main.tf` | `oci_containerengine_cluster` | endpoint、CNI、service LB subnet |
| 3 | `main.tf` | 查 node image | 架構要對 shape；**x86 image 名稱沒有架構字樣**，要用排除法 |
| 4 | `main.tf` | `oci_containerengine_node_pool` | Flex shape 需要 `node_shape_config`；A1／E4 擇一 |
| 5 | `outputs.tf` | kubeconfig 指令 | 字串插值 |

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars   # 填入 OCID、你的 IP、SSH 公鑰
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply          # cluster 約 5–10 分鐘，node 再 3–5 分鐘
```

> `.terraform.lock.hcl` 請一併 commit。

## 驗證方式

```bash
# 1. 產生 kubeconfig（指令直接取自 output）
terraform output -raw kubeconfig_command | bash
export KUBECONFIG=$HOME/.kube/oke-lab-config

# 2. 節點應為 Ready，架構為 arm64
kubectl get nodes -o wide
kubectl get nodes -L kubernetes.io/arch

# 3. 系統元件正常
kubectl get pods -A

# 4. 部署 nginx 並用 LoadBalancer 對外
kubectl create deployment web --image=nginx --replicas=2
kubectl expose deployment web --port=80 --type=LoadBalancer
kubectl get svc web -w            # 等 EXTERNAL-IP 出現（約 1–2 分鐘）
curl http://<EXTERNAL-IP>         # 應回 nginx 歡迎頁（只有 allowed_cidr 能連）
```

> ⚠️ nginx 官方 image 是多架構，可在 ARM 節點執行。自建 image 要確認有 `linux/arm64`。

## 結束

```bash
# ① 先刪 K8s 建立的 LB（否則 OCI LB 會殘留，且 VCN 刪不掉、持續計費）
kubectl delete svc web
kubectl get svc -A | grep LoadBalancer   # 確認沒有任何 LoadBalancer

# ② 再 destroy
terraform destroy -auto-approve

# ③ 確認沒有殘留
oci lb load-balancer list -c <compartment_id> --query 'data[].{n:"display-name",s:"lifecycle-state"}'
oci ce cluster list -c <compartment_id> --lifecycle-state ACTIVE
```

## 成本

| 項目 | 規格 | 費用 |
|------|------|------|
| OKE Control plane（BASIC） | — | **免費** |
| OKE Control plane（ENHANCED） | `cluster_type` 切換 | **約 US$0.10/hr**（≈ US$2.4/天）|
| Worker nodes（A1） | 2 × A1.Flex（1 OCPU / 6 GB） | Always Free 額度內 → **$0** |
| Worker nodes（E4）| 2 × E4.Flex（1 OCPU / 6 GB） | **💰 約 US$0.07/hr ≈ US$1.6/天**（見下方） |
| Boot volume | 2 × 50 GB | 額度內 → **$0**（合計 147 / 200 GB）|
| Flexible Load Balancer | 10 Mbps | 1 個免費 → **$0** |
| VCN / IGW / Security List | — | **免費** |

**Always Free A1 額度是整個帳號共用的：**

| | 總額 | `envs/oci-linux` 已用 | 本 lab 最多可用 |
|---|---|---|---|
| OCPU | 4 | 1 | **3** |
| 記憶體 | 24 GB | 6 GB | **18 GB** |
| Block volume | 200 GB | 47 GB | **153 GB** |

> ⚠️ 你的帳號是 PAYG，**沒有硬性上限**（`oci limits` 顯示可用 249 OCPU）。超出額度的 A1 會直接從信用卡／credit 扣款（約 US$0.01/OCPU/hr）。
> `variables.tf` 的 validation 擋住 `node_count × node_ocpus > 3`（A1 專用），用 A1 時不要為了繞過去而移除它。

### 改用 E4（x86）時的費用

A1 缺貨（`Out of host capacity`）時，可改用 `VM.Standard.E4.Flex`，容量通常充裕，但**不在 Always Free 內**：

| | A1.Flex | E4.Flex |
|---|---|---|
| 架構 | ARM（aarch64） | x86 |
| Always Free | ✅ 合計 4 OCPU / 24 GB | ❌ 全部計費 |
| 費用（參考定價） | $0 | 約 US$0.025/OCPU/hr + US$0.0015/GB/hr |
| 2 節點（1 OCPU / 6 GB） | $0 | ≈ US$0.07/hr ≈ **US$1.6/天** |
| Image 命名 | 含 `aarch64` | **無架構字樣**（排除 `aarch64`、`GPU`） |
| 額度護欄 | `variables.tf` validation | **無**（需註解掉 validation，自行控管） |

> 定價為參考值，請以 OCI Console 的 Cost Estimator 為準。
>
> ⚠️ 改用 E4 時要做三件事：① `node_shape` 改 `VM.Standard.E4.Flex`；② image 篩選改用排除法；③ 註解掉 `node_count`／`node_memory_gbs` 的 validation（否則會誤擋）。
>
> ⏰ credit 11/22 到期，**到期後 E4 會直接扣信用卡**。練完當天 `terraform destroy`，不要過夜。
>
> 💡 想體驗 ENHANCED（virtual node、add-on 管理）：趁 11/22 前用 credit 試，`cluster_type = "ENHANCED_CLUSTER"`，**記得當天 destroy**。

## 卡關提示

| 症狀 | 常見原因 |
|------|---------|
| `Out of host capacity` | A1 在 Singapore 缺貨（只有 1 個 AD）。指定 `fault_domains` 輪流試，或稍後重試。不是程式碼錯 |
| `LimitExceeded` / 配額錯誤 | 節點數 × OCPU 超出 Service Limit；先 `oci limits resource-availability get` 確認 |
| Node 一直 `NotReady` / 沒加入 | Security List 擋住 node → API(6443/12250)；或 image 架構與 shape 不符 |
| `Invalid index`（`locals` 的 `[0]`，collection has no elements） | image 篩選條件配不到任何東西。x86 image 名稱**沒有** `amd64`／`x86` 字樣，要改成排除 `aarch64` 與 `GPU` |
| 建立 node pool 時 image 錯誤 | 架構與 shape 不符（ARM image 配 E4、或 x86 image 配 A1）；或 image 版本與 `kubernetes_version` 不一致 |
| 改用 E4 後 `plan` 被 validation 擋住 | A1 專用的額度 validation 對 E4 不適用，需註解掉（並自行控管費用） |
| WSL 報 `did not find a proper configuration for tenancy` | WSL 沒有 `~/.oci/config` 與私鑰；建立指向 Windows 私鑰的 config，或改在 Windows Git Bash 執行 |
| `kubectl` 逾時 | `allowed_cidr` 不是你目前的對外 IP（IP 可能變了）；API endpoint 未設為 public |
| `kubectl` 回 `You must be logged in` | kubeconfig 的 token 過期／`oci` CLI 未設定；確認 `oci iam region list` 能執行 |
| `LoadBalancer` 的 EXTERNAL-IP 一直 `<pending>` | service LB subnet 設錯；或 LB 配額已用完（免費只有 1 個 10Mbps Flexible LB） |
| 能連 LB 但 502/逾時 | node Security List 沒放行 VCN 內流量到 NodePort（30000–32767） |
| `destroy` 卡在刪 subnet／VCN | K8s 建的 LB 還在 → 先 `kubectl delete svc`，或到 Console 手動刪 LB |
| `services_cidr` 衝突 | VCN CIDR 與 `10.96.0.0/16`／`10.244.0.0/16` 重疊 |
| 節點 SSH 連不上 | 沒放行 `allowed_cidr` 的 22；node 在 public subnet，使用者通常是 `opc` |

## 與 EKS（Lab 15）的對照

| | EKS | OKE |
|---|---|---|
| Control plane 費用 | US$0.10/hr | **Basic 免費**／Enhanced US$0.10/hr |
| 節點 | Managed Node Group | Node Pool |
| 認證 | `aws eks get-token` | `oci ce cluster generate-token`（kubeconfig 內建）|
| Pod 網路 | VPC CNI（預設，pod 用 VPC IP） | Flannel overlay（本 lab）或 VPC-native |
| Pod 對雲端權限 | IRSA | Workload Identity（Enhanced only） |
| LB | ALB／NLB | OCI Load Balancer（Flexible） |
