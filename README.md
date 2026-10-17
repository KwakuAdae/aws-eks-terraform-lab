# Lab: Deploy a Website to Amazon EKS with Terraform

A hands-on lab that builds an **Amazon EKS** cluster **entirely with Terraform** and deploys a
containerized website to it, also with Terraform. You write every piece yourself, with no
`eksctl` and no hidden community modules: VPC, subnets, NAT, IAM roles, the EKS control plane,
a managed node group, EKS add-ons, ECR, and the Kubernetes Deployment, Service, autoscaler and
disruption budget.

> Compare with [Deploy a Website to Amazon EKS](https://github.com/KwakuAdae/aws-eks-website-lab),
> which builds the same kind of cluster with **eksctl** and deploys with **kubectl + YAML**.
> Here, all of it is Terraform code you can read, review, version and destroy in one command.

```
 terraform/1-infra  ─────────────────────────────────────────────────────────────────────────────┐
 │  VPC 10.40.0.0/16                                                                              │
 │  ├─ public subnets  (2 AZs)  ← internet gateway, NAT gateway, load balancers                  │
 │  └─ private subnets (2 AZs)  ← worker nodes (route out via NAT)                                │
 │  EKS control plane (API auth mode, access entries) + IAM roles                                │
 │  Managed node group: 2 × t3.medium in private subnets                                         │
 │  Add-ons: vpc-cni · kube-proxy · coredns · metrics-server       ECR repo (immutable, scanned)  │
 └───────────────────────────── terraform.tfstate ── outputs: cluster name, region, ECR URL ─────┘
                                         │  terraform_remote_state
                                         ▼
 terraform/2-app  (Kubernetes provider) ──────────────────────────────────────────────────────────┐
 │  Namespace website · Deployment (2-6 pods) · Service type LoadBalancer (NLB) · HPA · PDB        │
 └────────────────────────────────────────────────────────────────────────────────────────────────┘
                                         │
              Browser ──HTTP:80──▶ Network Load Balancer ──▶ website pods (nginx, non-root, :8080)
```

## What you will learn

| Area | Topics |
|------|--------|
| **Terraform** | Providers, variables with validation, `count`, `for_each`, `cidrsubnet()`, data sources, `lifecycle { ignore_changes }`, outputs, **two-layer design** with `terraform_remote_state` |
| **Networking** | VPC, public/private subnets, NAT gateway, route tables, the `kubernetes.io/role/elb` subnet tags |
| **EKS** | Cluster IAM role, control-plane logging, **access entries** (`authentication_mode = "API"`), managed node groups, managed **add-ons** pinned to the latest compatible version |
| **Kubernetes via Terraform** | `kubernetes_deployment_v1`, `kubernetes_service_v1` (NLB), `kubernetes_horizontal_pod_autoscaler_v2`, `kubernetes_pod_disruption_budget_v1`, `wait_for_rollout`, provider auth with `aws_eks_cluster_auth` |
| **Operations** | Rolling updates by changing one variable, autoscaling, safe destroy order |

## Project structure

```
aws-eks-terraform-lab/
├── app/                         # website: nginx-unprivileged, /health, shows pod + version
├── terraform/
│   ├── 1-infra/                 # layer 1: AWS infrastructure
│   │   ├── versions.tf          # Terraform + AWS provider, default tags
│   │   ├── variables.tf
│   │   ├── vpc.tf               # VPC, subnets, IGW, NAT, routes
│   │   ├── eks.tf               # cluster IAM role, EKS cluster, log group
│   │   ├── nodes.tf             # node IAM role, managed node group
│   │   ├── addons.tf            # vpc-cni, kube-proxy, coredns, metrics-server
│   │   ├── ecr.tf               # ECR repository + lifecycle policy
│   │   ├── outputs.tf
│   │   └── terraform.tfvars.example
│   └── 2-app/                   # layer 2: the website on Kubernetes
│       ├── versions.tf          # reads layer 1 state, configures the Kubernetes provider
│       ├── variables.tf         # image_tag, replicas, HPA limits
│       ├── main.tf              # namespace, deployment, service, HPA, PDB
│       └── outputs.tf           # website_url
├── scripts/
│   ├── 01-create-infra.sh       # terraform apply (layer 1) + kubeconfig
│   ├── 02-build-push.sh         # build + push the image to ECR
│   ├── 03-deploy-app.sh         # terraform apply (layer 2) with an image tag
│   ├── 04-load-test.sh          # watch the HPA scale
│   └── 99-destroy.sh            # destroy layer 2, then layer 1
└── docs/
    ├── 01-terraform-explained.md
    └── 02-troubleshooting.md
```

## Prerequisites

| Tool | Check | Install |
|------|-------|---------|
| AWS account | — | ⚠️ EKS is **not** free tier, see [Cost](#cost) |
| AWS CLI v2 | `aws --version` | then `aws configure` |
| Terraform ≥ 1.5 | `terraform version` | `brew install terraform` |
| kubectl | `kubectl version --client` | `brew install kubectl` |
| Docker | `docker --version` | Docker Desktop |

Your IAM identity needs permissions for EKS, EC2/VPC, IAM, ECR, CloudWatch Logs and Elastic Load
Balancing (`AdministratorAccess` is simplest in a personal lab account). **The identity that runs
`terraform apply` becomes the cluster admin.**

---

## Quick start

```bash
git clone https://github.com/KwakuAdae/aws-eks-terraform-lab.git
cd aws-eks-terraform-lab

./scripts/01-create-infra.sh     # ~15-20 min
./scripts/02-build-push.sh v1
./scripts/03-deploy-app.sh v1    # prints the website URL
./scripts/99-destroy.sh          # IMPORTANT when you're done
```

---

## Step 1: Read the infrastructure code

Open [`terraform/1-infra`](terraform/1-infra). The highlights:

**Subnets with `count` and `cidrsubnet()`** ([`vpc.tf`](terraform/1-infra/vpc.tf)):

```hcl
resource "aws_subnet" "private" {
  count             = 2
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)  # 10.40.10.0/24, 10.40.11.0/24
  tags = { "kubernetes.io/role/internal-elb" = "1" }
}
```

The `kubernetes.io/role/elb` tag on public subnets tells EKS where to put internet-facing load balancers.

**Access entries instead of the `aws-auth` ConfigMap** ([`eks.tf`](terraform/1-infra/eks.tf)):

```hcl
access_config {
  authentication_mode                         = "API"
  bootstrap_cluster_creator_admin_permissions = true
}
```

**Add-ons always at the newest compatible version** ([`addons.tf`](terraform/1-infra/addons.tf)):

```hcl
data "aws_eks_addon_version" "latest" {
  for_each           = local.addons
  addon_name         = each.key
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}
```

`coredns` and `metrics-server` run as pods, so they're created **after** the node group
(`depends_on`); `vpc-cni` and `kube-proxy` go in first.

Line-by-line notes: [docs/01-terraform-explained.md](docs/01-terraform-explained.md).

## Step 2: Create the infrastructure

```bash
cd terraform/1-infra
cp terraform.tfvars.example terraform.tfvars    # optional: change region, sizes...
terraform init
terraform plan          # 29 resources to add
terraform apply         # type "yes", then wait ~15-20 minutes
```

or `./scripts/01-create-infra.sh`. Then connect kubectl:

```bash
$(terraform output -raw configure_kubectl)
kubectl get nodes
# NAME                          STATUS   ROLES    AGE   VERSION
# ip-10-40-10-57.ec2.internal   Ready    <none>   3m    v1.31.x
# ip-10-40-11-88.ec2.internal   Ready    <none>   3m    v1.31.x

kubectl get pods -n kube-system     # aws-node, kube-proxy, coredns, metrics-server
aws eks list-access-entries --cluster-name eks-tf-lab   # your IAM identity is listed
```

The node IPs are in `10.40.10.x` / `10.40.11.x`, the **private** subnets.

## Step 3: Build and push the image

```bash
./scripts/02-build-push.sh v1
```

The ECR repository came from Terraform (`ecr_repository_url` output). Tags are **immutable**, so
every release needs a new tag.

## Step 4: Deploy the website with Terraform

```bash
cd terraform/2-app
terraform init
terraform apply -var image_tag=v1
```

or `./scripts/03-deploy-app.sh v1`.

How layer 2 finds the cluster ([`2-app/versions.tf`](terraform/2-app/versions.tf)):

```hcl
data "terraform_remote_state" "infra" {          # read layer 1's outputs
  backend = "local"
  config  = { path = "${path.module}/../1-infra/terraform.tfstate" }
}

provider "kubernetes" {                          # log in to EKS with your AWS identity
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
```

> **Why two layers?** A Terraform provider can't be configured from a resource that doesn't
> exist yet. Putting the cluster and the Kubernetes objects in separate root modules avoids
> that problem. It also means app deploys never risk touching the cluster.

The `website_url` output is your NLB address:

```bash
terraform output website_url
# http://a1b2c3...elb.us-east-1.amazonaws.com
```

Open it. The page shows which **pod** served it and the **version** (`v1`). Refresh to see
different pods answer.

## Step 5: Ship a new version

```bash
./scripts/02-build-push.sh v2
./scripts/03-deploy-app.sh v2
```

Terraform's plan shows exactly one change, the container `image` (and `APP_VERSION`). With
`max_unavailable = 0` and `wait_for_rollout = true`, Kubernetes replaces pods one by one and
Terraform waits until the rollout succeeds. Watch it:

```bash
kubectl get pods -n website -w
```

**Rollback** = apply the previous tag: `./scripts/03-deploy-app.sh v1`.

## Step 6: Autoscaling

```bash
./scripts/04-load-test.sh 180
# NAME      REFERENCE            TARGETS        MINPODS   MAXPODS   REPLICAS
# website   Deployment/website   cpu: 8%/60%    2         6         2
# website   Deployment/website   cpu: 140%/60%  2         6         5
```

The Deployment uses `lifecycle { ignore_changes = [spec[0].replicas] }`, so the next `terraform
apply` won't fight the autoscaler.

## Step 7: Change infrastructure safely

Try a change and **read the plan before applying**:

```bash
cd terraform/1-infra
terraform plan -var node_max_size=4         # 1 to change: node group scaling, updated in place
terraform plan -var vpc_cidr=10.50.0.0/16   # forces REPLACEMENT of the VPC and everything in it. Don't apply!
```

Learning to tell "update in place" from "must be replaced" is the most important Terraform skill.

## Step 8: Clean up

```bash
./scripts/99-destroy.sh
```

Order matters: **layer 2 first**. Deleting the Kubernetes Service makes AWS delete the NLB. If you
destroy the cluster first, the NLB is orphaned and blocks VPC deletion.

---

## Cost

| Resource | Approx. cost (us-east-1) |
|----------|--------------------------|
| EKS control plane | $0.10 / hour |
| 2 × t3.medium nodes | ~$0.083 / hour |
| NAT gateway | ~$0.045 / hour + data |
| Network Load Balancer | ~$0.0225 / hour |
| ECR, CloudWatch Logs | cents |

**About $0.25 per hour.** Run `./scripts/99-destroy.sh` when you finish.

## Going further

- **Remote state**: S3 backend with state locking (see [docs/01-terraform-explained.md](docs/01-terraform-explained.md#remote-state))
- **Ingress**: install the AWS Load Balancer Controller with the `helm` provider and use an ALB
- **Pod Identity**: add the `eks-pod-identity-agent` add-on and an `aws_eks_pod_identity_association`
- **Karpenter** for node autoscaling
- **CI/CD**: `terraform plan` on pull requests, `apply` on merge (GitHub Actions + OIDC)
- Refactor `1-infra` into reusable **modules** (`modules/vpc`, `modules/eks`)
- Sister labs: [EKS with eksctl](https://github.com/KwakuAdae/aws-eks-website-lab) ·
  [EKS microservices](https://github.com/KwakuAdae/aws-eks-microservices-lab) ·
  [CloudWatch Logs + Terraform](https://github.com/KwakuAdae/aws-cloudwatch-logs-terraform-lab) ·
  [Advanced Fargate](https://github.com/KwakuAdae/aws-ecs-fargate-advanced-lab)

## Troubleshooting

See [docs/02-troubleshooting.md](docs/02-troubleshooting.md).

## Author

**Kwaku Adae**: [github.com/KwakuAdae](https://github.com/KwakuAdae)

Feedback and reviews are welcome. Open an issue or a pull request!
