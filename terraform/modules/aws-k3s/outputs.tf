# ============================================================================
# Outputs
# ============================================================================

# Azure Outputs
output "azure_vm_name" {
  description = "Azure VM name"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "azure_vm_private_ip" {
  description = "Azure VM private IP address"
  value       = azurerm_network_interface.nic.private_ip_address
}

# AWS Outputs
output "aws_instance_id" {
  description = "AWS EC2 control plane instance ID"
  value       = aws_instance.k3s_cp.id
}

output "aws_instance_private_ip" {
  description = "AWS EC2 control plane private IP address"
  value       = aws_instance.k3s_cp.private_ip
}

output "aws_eip_public_ip" {
  description = "AWS EC2 control plane Elastic IP (stable public IP for kubeconfig)"
  value       = aws_eip.k3s_cp.public_ip
}

output "aws_instance_public_dns" {
  description = "AWS EC2 control plane public DNS name"
  value       = aws_instance.k3s_cp.public_dns
}

output "worker_instance_ids" {
  description = "AWS EC2 worker node instance IDs"
  value       = aws_instance.k3s_worker[*].id
}

output "worker_private_ips" {
  description = "AWS EC2 worker node private IP addresses"
  value       = aws_instance.k3s_worker[*].private_ip
}

output "worker_public_ips" {
  description = "AWS EC2 worker node public IP addresses"
  value       = aws_instance.k3s_worker[*].public_ip
}

# Instructions
output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    ========================================
    Multi-Cloud K3s Lab Deployed!
    ========================================

    Azure VM:       ${azurerm_linux_virtual_machine.vm.name}
    AWS CP:         ${aws_instance.k3s_cp.id}
    AWS Workers:    ${join(", ", aws_instance.k3s_worker[*].id)}
    AWS EIP:        ${aws_eip.k3s_cp.public_ip}

    Next Steps:

    1. Wait for cloud-init to complete (~3-5 minutes):

       # Check CP (Azure Run Command not needed for AWS — use console output)
       aws ec2 get-console-output \
         --instance-id ${aws_instance.k3s_cp.id} \
         --region ${var.aws_region} | grep "Setup complete"

       # Check workers
       aws ec2 get-console-output \
         --instance-id ${aws_instance.k3s_worker[0].id} \
         --region ${var.aws_region} | grep "Setup complete"

    2. Check Tailscale devices:
       https://login.tailscale.com/admin/machines

       You should see:
       - k3s-cp (AWS control plane) ✓
       - k3s-worker-0 (AWS worker) ✓
       - k3s-worker-1 (AWS worker) ✓

    3. Get kubeconfig:
       EIP="${aws_eip.k3s_cp.public_ip}"
       tailscale ssh ubuntu@k3s-cp "sudo cat /etc/rancher/k3s/k3s.yaml" \
         | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
         > kubeconfig/k3s-aws.yaml

    4. Verify all nodes are Ready:
       KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

       Expected:
       NAME           STATUS   ROLES                  AGE
       k3s-cp         Ready    control-plane,master   Xm
       k3s-worker-0   Ready    <none>                 Xm
       k3s-worker-1   Ready    <none>                 Xm

    5. Stop instances to save cost when not in use:
       aws ec2 stop-instances \
         --instance-ids ${aws_instance.k3s_cp.id} ${join(" ", aws_instance.k3s_worker[*].id)} \
         --region ${var.aws_region}

    ========================================
    Troubleshooting:

    CP cloud-init log:
      aws ec2 get-console-output --instance-id ${aws_instance.k3s_cp.id} --region ${var.aws_region}

    Worker cloud-init log (Tailscale SSH):
      tailscale ssh ubuntu@k3s-worker-0 "tail -50 /var/log/user-data.log"

    SSM token check:
      aws ssm get-parameter --name /k3s-lab/node-token --with-decryption --region ${var.aws_region}

    Clean up SSM after destroy:
      aws ssm delete-parameter --name /k3s-lab/node-token --region ${var.aws_region}
    ========================================
  EOT
}
