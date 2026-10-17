# Troubleshooting

## Terraform: layer 1 (infra)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `No valid credential sources found` | AWS CLI not configured | `aws configure` or `export AWS_PROFILE=...` |
| `UnsupportedAvailabilityZoneException` creating the cluster | EKS doesn't support one of the first two AZs in that region (rare, e.g. us-east-1e) | Re-run apply; or hard-code `locals.azs` to supported zones |
| `InvalidParameterException: unsupported Kubernetes version` | Version not offered (too old/new) | `aws eks describe-cluster-versions --query 'clusterVersions[].clusterVersion'` and set `kubernetes_version` |
| Add-on stuck `CREATING` then `DEGRADED` | Nodes not ready yet, or too small | `kubectl get nodes`; check `aws eks describe-addon --cluster-name eks-tf-lab --addon-name coredns` |
| Node group fails: `Ec2SubnetInvalidConfiguration` / nodes `NotReady` | Private subnets can't reach the internet | Check the private route table points to the NAT gateway |
| `EntityAlreadyExists` for IAM roles | Leftovers from an earlier run | Change `cluster_name`, or delete the old roles |
| Apply interrupted, state lock / partial state | Ctrl+C or network drop | Run `terraform apply` again. Terraform picks up where it stopped |

## kubectl access

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `You must be logged in to the server (Unauthorized)` | You're using a different IAM identity than the one that ran `terraform apply` | Use the same profile, or add an access entry: `aws eks create-access-entry` + `aws eks associate-access-policy --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope type=cluster` |
| `couldn't get current server API group list` | kubeconfig not set | `$(terraform -chdir=terraform/1-infra output -raw configure_kubectl)` |

## Terraform: layer 2 (app)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `Unable to find remote state` | Layer 1 not applied, or its state file moved | Apply `1-infra` first; keep the folder layout |
| `Unauthorized` from the Kubernetes provider | Token for a different IAM identity | Same fix as kubectl above |
| `Waiting for rollout to finish: 0 of 2 updated replicas are available` then timeout | Pods can't start | `kubectl describe pod -n website -l app.kubernetes.io/name=website`: usually `ImagePullBackOff` (tag not pushed) |
| `ImagePullBackOff` | Tag doesn't exist in ECR | `./scripts/02-build-push.sh <tag>` first; `aws ecr list-images --repository-name eks-tf-website` |
| `CrashLoopBackOff` / `exec format error` | Image built for ARM (Apple Silicon) | The script uses `--platform linux/amd64`. Rebuild with a new tag |
| `wait_for_load_balancer` times out | Subnets missing ELB tags, or account limits | `kubectl describe svc website -n website` shows the reason. Public subnets need `kubernetes.io/role/elb = 1` |
| Website URL doesn't resolve | New NLB DNS still propagating | Wait 1–3 minutes |
| HPA shows `<unknown>/60%` | metrics-server add-on not ready | `kubectl get deploy metrics-server -n kube-system` |

## Destroy

| Symptom | Fix |
|---------|-----|
| `1-infra` destroy hangs on subnets/VPC (`DependencyViolation`) | A load balancer or its ENIs still exist. Destroy `2-app` first; otherwise delete leftover `k8s-*` / `a1b2...` load balancers in EC2 → Load Balancers, then retry |
| `2-app` destroy fails because the cluster is already gone | Remove its state (`rm terraform/2-app/terraform.tfstate*`), then check for leftover load balancers |
