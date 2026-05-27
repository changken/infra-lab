output "alb_dns_name" {
  description = "ALB DNS 名稱（HTTP 測試入口）"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "asg_name" {
  description = "Auto Scaling Group 名稱"
  value       = aws_autoscaling_group.web.name
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.web.arn
}

output "curl_command" {
  description = "驗證 ALB 是否正常回應的 curl 指令"
  value       = "curl http://${aws_lb.main.dns_name}"
}

output "asg_status_command" {
  description = "查詢 ASG 目前 EC2 數量與狀態的 CLI 指令"
  value       = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${aws_autoscaling_group.web.name} --query 'AutoScalingGroups[0].{Min:MinSize,Max:MaxSize,Desired:DesiredCapacity,Instances:length(Instances)}' --output table"
}

output "target_group_health_command" {
  description = "查詢 Target Group 健康狀態的 CLI 指令"
  value       = "aws elbv2 describe-target-health --target-group-arn ${aws_lb_target_group.web.arn} --query 'TargetHealthDescriptions[*].{ID:Target.Id,Port:Target.Port,State:TargetHealth.State}' --output table"
}
