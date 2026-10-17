# The Terraform Code Explained

## Why two root modules?

| | `terraform/1-infra` | `terraform/2-app` |
|---|---|---|
| Creates | VPC, EKS, nodes, add-ons, ECR, IAM | Namespace, Deployment, Service, HPA, PDB |
| Providers | `aws` | `aws` (to look up the cluster) + `kubernetes` |
| Changes | Rarely | Every release |
| Apply time | 15–20 min | 1–3 min |

The Kubernetes provider needs the cluster's endpoint and certificate **when Terraform starts**.
If the cluster were created in the same apply, those values would be unknown, and the provider
fails or behaves unpredictably. Separating the layers is the pattern HashiCorp recommends.

Layer 2 reads layer 1's outputs with `terraform_remote_state`:

```hcl
data "terraform_remote_state" "infra" {
  backend = "local"
  config  = { path = "${path.module}/../1-infra/terraform.tfstate" }
}
# then: data.terraform_remote_state.infra.outputs.ecr_repository_url
```

## Resource walkthrough (`1-infra`)

### `vpc.tf`

| Resource | Notes |
|----------|-------|
| `data.aws_availability_zones` + `slice(..., 0, 2)` | Uses the first two AZs in whichever region you pick |
| `aws_subnet.public[count]` | `cidrsubnet("10.40.0.0/16", 8, 0..1)` → `10.40.0.0/24`, `10.40.1.0/24`. Tag `kubernetes.io/role/elb = 1` |
| `aws_subnet.private[count]` | `cidrsubnet(..., 8, 10..11)` → `10.40.10.0/24`, `10.40.11.0/24`. Tag `kubernetes.io/role/internal-elb = 1` |
| `aws_nat_gateway` | One NAT (cheaper). For production, one per AZ |
| `aws_route_table.*` + associations | Public → IGW, private → NAT |

### `eks.tf`

- **Cluster role** trusted by `eks.amazonaws.com`, with `AmazonEKSClusterPolicy`.
- `vpc_config` uses **all four subnets**, so EKS can place load balancers and control-plane ENIs.
  Public **and** private endpoint access: kubectl works from your laptop, and nodes reach the API privately.
- `access_config.authentication_mode = "API"` uses **access entries**, managed with the EKS API
  (`aws eks list-access-entries`, `aws_eks_access_entry` in Terraform) instead of editing the
  `aws-auth` ConfigMap.
- `enabled_cluster_log_types` sends API, audit and authenticator logs to CloudWatch. The log group
  is created by Terraform so it has a **7-day retention** (otherwise logs are kept forever).

### `nodes.tf`

- Node role with the three standard policies (`AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryReadOnly`), attached with `for_each = toset([...])`.
- `aws_eks_node_group` in the **private** subnets.
- `lifecycle { ignore_changes = [scaling_config[0].desired_size] }`: a node autoscaler can change
  the size without the next `terraform apply` reverting it.

### `addons.tf`

- One map, two resources: add-ons that run as DaemonSets (`vpc-cni`, `kube-proxy`) are installed
  immediately; those that run as Deployments (`coredns`, `metrics-server`) wait for the node group
  so they can become `ACTIVE`.
- `data.aws_eks_addon_version` with `most_recent = true` picks the newest version compatible with
  the cluster's Kubernetes version.

### `ecr.tf`

`image_tag_mutability = "IMMUTABLE"`, scan on push, `force_delete = true` (destroy works even with
images inside), and a lifecycle policy keeping 10 images.

## Resource walkthrough (`2-app`)

| Resource | Notes |
|----------|-------|
| `kubernetes_namespace_v1` | Everything lives in `website` |
| `kubernetes_deployment_v1` | `wait_for_rollout = true`, `max_unavailable = 0`, probes on `/health`, non-root, `ignore_changes = [spec[0].replicas]` for the HPA |
| `kubernetes_service_v1` | `type = LoadBalancer` + annotation `aws-load-balancer-type: nlb` → a Network Load Balancer; `wait_for_load_balancer = true` so the URL output is ready |
| `kubernetes_horizontal_pod_autoscaler_v2` | 2–6 pods at 60% CPU (needs the metrics-server add-on) |
| `kubernetes_pod_disruption_budget_v1` | At least 1 pod stays up during node drains |

## Remote state

Local state files are fine for a solo lab. For a team, store state in S3 with locking. Add this
to both `versions.tf` files (with different `key`s), then run `terraform init -migrate-state`:

```hcl
terraform {
  backend "s3" {
    bucket       = "my-terraform-state-123456789012"
    key          = "eks-tf-lab/1-infra.tfstate"
    region       = "us-east-1"
    use_lockfile = true      # S3-native state locking (Terraform 1.10+)
    encrypt      = true
  }
}
```

and change `2-app`'s `terraform_remote_state` to `backend = "s3"` with the same bucket and key.

## Useful commands

```bash
terraform fmt -recursive          # format all files
terraform validate                # check syntax and references
terraform plan -out=tfplan        # save a plan...
terraform apply tfplan            # ...and apply exactly that plan
terraform state list              # what Terraform manages
terraform state show aws_eks_cluster.main
terraform output                  # all outputs
terraform graph | dot -Tpng > graph.png   # dependency graph (needs graphviz)
```
