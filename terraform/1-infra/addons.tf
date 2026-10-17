# ---------------------------------------------------------------------------
# EKS managed add-ons
# ---------------------------------------------------------------------------

locals {
  addons = {
    "vpc-cni"        = { needs_nodes = false } # pod networking
    "kube-proxy"     = { needs_nodes = false } # service networking
    "coredns"        = { needs_nodes = true }  # cluster DNS (runs as pods)
    "metrics-server" = { needs_nodes = true }  # CPU/memory metrics for the HPA (runs as pods)
  }
}

data "aws_eks_addon_version" "latest" {
  for_each           = local.addons
  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "before_nodes" {
  for_each                    = { for name, a in local.addons : name => a if !a.needs_nodes }
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.latest[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# coredns and metrics-server are Deployments, so they need nodes to become ACTIVE
resource "aws_eks_addon" "after_nodes" {
  for_each                    = { for name, a in local.addons : name => a if a.needs_nodes }
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.latest[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.main]
}
