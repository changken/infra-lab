# O-08：CPU 自架 LLM（E5 Flex）

> 在 OCI 開一台 `VM.Standard.E5.Flex`，用 llama.cpp 或 Ollama 跑 7B–8B Q4 量化模型，對標 AWS 的 EC2（CPU 推論），並與 O-03 的託管 GenAI 比延遲與每百萬 token 成本。
>
> 💰 **成本等級：🔴 付費（無 Always Free）**。單價待 Cost Estimator 確認。
>
> ⏰ **credit 11/22 到期**。**11/21 前必須 `terraform destroy`**，並用 `oci` CLI 確認沒有殘留。

## 現況

這台是在 Console **手動建立**後，用 `terraform import` 納管（不是從零 apply），規格與規劃不同：

| 項目 | 規劃 | 現況（import） |
|---|---|---|
| Shape | `VM.Standard.E5.Flex` | 同 |
| OCPU / 記憶體 | 8 / 64 GB | **23 / 276 GB** |
| Boot volume | — | **1024 GB，VPU 30（ultra high）** |
| Subnet | — | `public-subnet-one`（`envs/oci-vcn`），有公網 IP |

- boot volume 不能縮小，要縮到規劃值只能重建實例。
- OCPU / 記憶體可用 `ocpus`、`memory_in_gbs` 調整（resize 需重開機）。
- 名稱、hostname、內網 IP、規格都在 `variables.tf`，不寫死在 `main.tf`。

## 檔案

| 檔案 | 說明 |
|---|---|
| `variables.tf` | 名稱、hostname、IP、shape、規格、boot volume 等（預設值為 import 現況） |
| `locals.tf` | `common_tags` |
| `main.tf` | `oci_core_instance.llm` |
| `outputs.tf` | `instance_id`、`public_ip`、`private_ip`、`ssh_command` |

## 指令

```bash
cp terraform.tfvars.example terraform.tfvars   # 填 compartment / subnet / SSH 公鑰 / image OCID
terraform init
terraform import oci_core_instance.llm <instance_ocid>   # 已完成；重建 state 時才需要
terraform fmt && terraform validate
terraform plan
```

⚠️ plan 若出現 `must be replaced`（常見原因：`metadata`、`source_details`）**不要 apply**。
`ssh_authorized_keys` 這台沒有結尾換行，加 `\n` 會觸發 replace。

## 驗證

```bash
terraform output -raw ssh_command                  # image 為 Ubuntu 26.04，帳號 ubuntu
oci compute instance get --instance-id $(terraform output -raw instance_id) \
  --query 'data."lifecycle-state"'
```

## 結束

```bash
terraform destroy -auto-approve
oci compute instance list -c <compartment> --lifecycle-state RUNNING   # 確認沒有 E5 殘留
```

## 成本

- 無 Always Free 可用，全部耗 credit，11/22 後直接扣信用卡。
- 現況規格（23 OCPU / 276 GB / 1024 GB ultra high）比規劃（8 OCPU / 64 GB）貴數倍，單價待 Cost Estimator。
- 額度：`standard-e5-core-count` 83、`standard-e5-memory-count` 1250（2026-11-16 查），目前未超額。

## 卡關提示

| 症狀 | 原因 |
|---|---|
| plan 顯示 `must be replaced`，標在 `metadata` | `ssh_authorized_keys` 多了結尾 `\n` |
| plan 顯示 `must be replaced`，標在 `source_details` | image 改動，需在 `ignore_changes` 內 |
| 縮小 boot volume 失敗 | boot volume 只能放大不能縮小 |
