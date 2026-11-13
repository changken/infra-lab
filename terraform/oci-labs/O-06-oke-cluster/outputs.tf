output "cluster_id" {
  description = "OKE cluster OCID"
  value       = oci_containerengine_cluster.this.id
}

output "api_endpoint" {
  description = "K8s API 公開端點"
  value       = oci_containerengine_cluster.this.endpoints[0].public_endpoint
}

#--------------------------------------------------------------
# TODO 5: 產生 kubeconfig 的指令
#--------------------------------------------------------------
# 文件: https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm
#
# 組出一行可直接複製執行的 oci CLI 指令，需要：
#   oci ce cluster create-kubeconfig
#     --cluster-id <cluster id>
#     --file $HOME/.kube/oke-lab-config      # 另存，不要覆蓋你原本的 ~/.kube/config
#     --region <region>
#     --token-version 2.0.0
#     --kube-endpoint PUBLIC_ENDPOINT
#
# 💡 提示：用字串插值把 oci_containerengine_cluster.this.id 與 var.region 帶進去

output "kubeconfig_command" {
  description = "產生 kubeconfig 的指令"
  # 單行輸出，才能 `terraform output -raw kubeconfig_command | bash`
  value = join(" ", [
    "oci ce cluster create-kubeconfig",
    "--cluster-id ${oci_containerengine_cluster.this.id}",
    "--file $HOME/.kube/oke-lab-config",
    "--region ${var.region}",
    "--token-version 2.0.0",
    "--kube-endpoint PUBLIC_ENDPOINT",
  ])
}