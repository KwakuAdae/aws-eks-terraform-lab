output "website_url" {
  description = "Open this in your browser (DNS can take a minute or two the first time)"
  value       = "http://${kubernetes_service_v1.website.status[0].load_balancer[0].ingress[0].hostname}"
}

output "image" {
  value = "${local.ecr_url}:${var.image_tag}"
}

output "namespace" {
  value = kubernetes_namespace_v1.website.metadata[0].name
}
