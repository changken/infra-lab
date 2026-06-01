# ============================================================================
# Outputs
# ============================================================================

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

output "next_steps" {
  description = "Next steps after deployment"
  value       = <<-EOT
    ========================================
    AWS K3s Cluster Deployed!
    ========================================

    CP:      ${aws_instance.k3s_cp.id}
    Workers: ${join(", ", aws_instance.k3s_worker[*].id)}
    EIP:     ${aws_eip.k3s_cp.public_ip}

    1. Wait for cloud-init (~3-5 minutes):

       aws ec2 get-console-output \
         --instance-id ${aws_instance.k3s_cp.id} \
         --region ${var.aws_region} | grep "Setup complete"

       aws ec2 get-console-output \
         --instance-id ${aws_instance.k3s_worker[0].id} \
         --region ${var.aws_region} | grep "Setup complete"

    2. Check Tailscale devices:
       https://login.tailscale.com/admin/machines
       - ${var.cp_hostname} ✓
%{for i in range(var.worker_count)~}
       - ${var.worker_hostname_prefix}-${i + 1} ✓
%{endfor~}

    3. Get kubeconfig:
       EIP="${aws_eip.k3s_cp.public_ip}"
       tailscale ssh ubuntu@${var.cp_hostname} "sudo cat /etc/rancher/k3s/k3s.yaml" \
         | sed "s|https://127.0.0.1:6443|https://$EIP:6443|g" \
         > kubeconfig/k3s-aws.yaml

    4. Verify nodes:
       KUBECONFIG=kubeconfig/k3s-aws.yaml kubectl get nodes

       Expected:
       NAME                    STATUS   ROLES                  AGE
       ${var.cp_hostname}      Ready    control-plane,master   Xm
%{for i in range(var.worker_count)~}
       ${var.worker_hostname_prefix}-${i + 1}   Ready    <none>                 Xm
%{endfor~}

    5. Stop to save cost:
       aws ec2 stop-instances \
         --instance-ids ${aws_instance.k3s_cp.id} ${join(" ", aws_instance.k3s_worker[*].id)} \
         --region ${var.aws_region}

    ========================================
    Troubleshooting:

    CP log:
      aws ec2 get-console-output --instance-id ${aws_instance.k3s_cp.id} --region ${var.aws_region}

    Worker log (via Tailscale SSH):
      tailscale ssh ubuntu@${var.worker_hostname_prefix}-1 "tail -50 /var/log/user-data.log"

    SSM token:
      aws ssm get-parameter --name /k3s-lab/node-token --with-decryption --region ${var.aws_region}

    Clean up SSM after destroy:
      aws ssm delete-parameter --name /k3s-lab/node-token --region ${var.aws_region}
      aws ssm delete-parameter --name /k3s-lab/tailscale-auth-key --region ${var.aws_region}
    ========================================
  EOT
}
