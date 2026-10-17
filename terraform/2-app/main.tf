# ---------------------------------------------------------------------------
# The website, deployed with the Terraform Kubernetes provider
# ---------------------------------------------------------------------------

locals {
  labels = {
    "app.kubernetes.io/name"       = "website"
    "app.kubernetes.io/managed-by" = "terraform"
  }
  selector = { "app.kubernetes.io/name" = "website" }
}

resource "kubernetes_namespace_v1" "website" {
  metadata {
    name   = var.namespace
    labels = local.labels
  }
}

resource "kubernetes_deployment_v1" "website" {
  metadata {
    name      = "website"
    namespace = kubernetes_namespace_v1.website.metadata[0].name
    labels    = local.labels
  }

  # Wait until the rollout finishes (or fails) before Terraform reports success
  wait_for_rollout = true

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.selector
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0" # zero-downtime rollouts
      }
    }

    template {
      metadata {
        labels = merge(local.labels, local.selector)
      }

      spec {
        security_context {
          run_as_non_root = true
          seccomp_profile { type = "RuntimeDefault" }
        }

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = local.selector
          }
        }

        container {
          name  = "website"
          image = "${local.ecr_url}:${var.image_tag}"

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name = "POD_NAME"
            value_from {
              field_ref { field_path = "metadata.name" }
            }
          }
          env {
            name  = "APP_VERSION"
            value = var.image_tag
          }

          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "250m", memory = "128Mi" }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            period_seconds = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }

          security_context {
            allow_privilege_escalation = false
            capabilities { drop = ["ALL"] }
          }
        }
      }
    }
  }

  # The HPA owns the replica count after the first apply
  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

resource "kubernetes_service_v1" "website" {
  metadata {
    name      = "website"
    namespace = kubernetes_namespace_v1.website.metadata[0].name
    labels    = local.labels
    annotations = {
      # Ask AWS for a Network Load Balancer instead of the default Classic Load Balancer
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
  }

  spec {
    type     = "LoadBalancer"
    selector = local.selector

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }
  }

  # Wait for AWS to assign the load balancer hostname
  wait_for_load_balancer = true
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "website" {
  metadata {
    name      = "website"
    namespace = kubernetes_namespace_v1.website.metadata[0].name
    labels    = local.labels
  }

  spec {
    min_replicas = var.hpa_min
    max_replicas = var.hpa_max

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.website.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 60
        }
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "website" {
  metadata {
    name      = "website"
    namespace = kubernetes_namespace_v1.website.metadata[0].name
    labels    = local.labels
  }

  spec {
    min_available = "1" # node drains/upgrades never take every pod down at once
    selector {
      match_labels = local.selector
    }
  }
}
