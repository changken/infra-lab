output "cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "Task definition ARN（含版本號）"
  value       = aws_ecs_task_definition.app.arn
}

# ECS Fargate 的 Public IP 是動態分配的（每次 task 重啟可能不同）。
# Terraform 無法直接輸出，改用以下指令取得：
output "get_public_ip_commands" {
  description = "Commands to retrieve the running task's public IP"
  value       = <<-EOF
    # Step 1: 取得 Task ARN
    aws ecs list-tasks \
      --cluster ${aws_ecs_cluster.main.name} \
      --service-name ${aws_ecs_service.app.name} \
      --query 'taskArns[0]' --output text

    # Step 2: 取得 ENI ID（把 <task-arn> 換成上面的結果）
    aws ecs describe-tasks \
      --cluster ${aws_ecs_cluster.main.name} \
      --tasks <task-arn> \
      --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
      --output text

    # Step 3: 取得 Public IP（把 <eni-id> 換成上面的結果）
    aws ec2 describe-network-interfaces \
      --network-interface-ids <eni-id> \
      --query 'NetworkInterfaces[0].Association.PublicIp' \
      --output text
  EOF
}
