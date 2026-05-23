output "metrics_server_status" {
  description = "Helm release status for metrics-server"
  value       = helm_release.metrics_server.status
}

output "ingress_nginx_status" {
  description = "Helm release status for ingress-nginx"
  value       = helm_release.ingress_nginx.status
}

output "ingress_nginx_namespace" {
  description = "Namespace where ingress-nginx is deployed"
  value       = helm_release.ingress_nginx.namespace
}

output "verify_metrics_command" {
  description = "Run this after apply to verify metrics-server is working"
  value       = "kubectl top nodes"
}

output "verify_ingress_command" {
  description = "Run this to get the ELB hostname of the ingress controller"
  value       = "kubectl get svc -n ingress-nginx ingress-nginx-controller"
}
