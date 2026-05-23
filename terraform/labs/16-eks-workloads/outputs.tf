output "namespace" {
  description = "Kubernetes namespace where the app is deployed"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "deployment_name" {
  description = "Kubernetes Deployment name"
  value       = kubernetes_deployment.app.metadata[0].name
}

output "service_hostname" {
  description = "AWS ELB hostname assigned to the LoadBalancer Service (may take 1-2 minutes)"
  value       = kubernetes_service.app.status[0].load_balancer[0].ingress[0].hostname
}

output "service_url" {
  description = "Application URL"
  value       = "http://${kubernetes_service.app.status[0].load_balancer[0].ingress[0].hostname}"
}
