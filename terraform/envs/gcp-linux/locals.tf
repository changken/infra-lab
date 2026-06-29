locals {
  # GCP labels 為 map(string)，key/value 均需小寫
  labels = {
    project    = var.project
    env        = var.environment
    managed-by = "terraform"
  }

  # Network tag：用於將 Firewall rule 套用到特定 VM
  ssh_tag = "allow-ssh-from-my-ip"
}
