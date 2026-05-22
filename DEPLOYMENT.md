# Deployment Playbook — Skillpulse on EKS

Step-by-step commands to deploy the full stack. Run these in order.

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.5.7
- kubectl
- Helm 3 (`brew install helm`)
- Docker (for local image builds)
- GitHub repo secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, `MAIL_USERNAME`, `MAIL_PASSWORD`, `FRONTEND_URL`, `BACKEND_URL`, `KUBECONFIG_DATA`

>Generate kubeconfig secret:
>cat ~/.kube/config | base64 -w 0
>Then add output to:
>GitHub Repo → Settings → Secrets → Actions.

## Step 1: Provision Infrastructure

```bash
cd terraform
# s3 + dynamo db create
cd bootstrap
terraform init 
terraform plan 
terraform apply
# creates modules
cd ..
terraform init
terraform plan -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
# Takes ~15 minutes — creates VPC, EKS cluster (3 nodes), ArgoCD, Envoy-Gateway, cert-manager, kube-prometheus-stack
```

## Step 2: Configure kubectl

```bash
aws eks update-kubeconfig --name < eks-cluster-name > --region us-west-2
kubectl get nodes
# Should show 3 nodes in Ready state
```

## Step 3: Verify ArgoCD

```bash
# Check all pods are Running
kubectl get pods -n argocd

# Get ArgoCD URL
kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo

# Login: admin / <password>
```
## Step 3: Deploy the entire application stack in order:

```bash
cd ..

# 1. Namespace and storage
kubectl apply -f k8s/00-namespace.yml

# 2. Configuration
kubectl apply -f k8s/10-secrets-sa.yaml

# 3. Database 
kubectl apply -f k8s/20-mysql.yaml

# 4. Application
kubectl apply -f k8s/30-backend.yaml
kubectl apply -f k8s/40-frontend.yaml
kubectl apply -f k8s/50-hpa.yml
kubectl apply -f k8s/80-backup.yaml

```
## Step 4: Deploy Gateway API + Envoy Gateway

```bash
# Deploy Envoy gateway
kubectl apply -f k8s/60-gateway.yml
# Verify
kubectl get gatewayclass
kubectl get gateway -n skillpulse
nslookup <gateway-lb-hostname>
```

## Step 5: Deploy cert-manager (TLS/HTTPS)

```bash
# Deploy cert-manager
kubectl apply -f k8s/70-cert-manager.yml
# Verify
kubectl get pods -n cert-manager
```

After ArgoCD syncs the ClusterIssuer and updated Gateway (with HTTPS listener), cert-manager automatically provisions a Let's Encrypt TLS certificate.

**Prerequisite:** Create a CNAME in GoDaddy:
- `<your-domain>` → `<NLB hostname from Step 4>`
```bash
# Check certificate status
kubectl get certificate -n skillpulse
kubectl get secret skillpulse-tls -n skillpulse
```

## step 6: Free Certificate Access Note

Resolve that hostname to an IP address and update k8s/60-gateway.yaml with the new value in the hosts field.

nslookup <gateway-lb-hostname>
For example, if the resolved IP is 52.42.53.147, the application will be accessible at:

```bash
52.42.53.147.nip.io
```
This keeps the certificate and host-based routing aligned with the current Gateway load balancer address.

## Step 7: Verify kube-prometheus-stack

```bash
# Get Grafana URL
kubectl get svc kube-prometheus-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Get Grafana password
kubectl get secret kube-prometheus-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo

# Login: admin / <password>
```

## Step 8: Deploy via ArgoCD

```bash
kubectl apply -f argocd/application.yml

# Watch sync progress
kubectl get application bankapp -n argocd -w
```

## Step 9: Verify Everything

```bash
# All pods should be Running
kubectl get pods -n skillpulse

# Check PVCs are Bound
kubectl get pvc -n skillpulse

# Check Gateway has an address
kubectl get gateway -n skillpulse

# Get the app URL (NLB created by Envoy Gateway)
kubectl get svc -n envoy-gateway-system \
  -l gateway.envoyproxy.io/owning-gateway-name=bankapp-gateway \
  -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'

# Test — should return 302 (Spring Security redirect to /login)
curl -s -o /dev/null -w "%{http_code}" http://<APP_URL>/

# Test login page — should return 200
curl -s -o /dev/null -w "%{http_code}" -L http://<APP_URL>/login
```

## Cleanup

> **ORDER MATTERS.** Helm-installed resources (Envoy Gateway, Grafana) create AWS Load Balancers
> and Security Groups outside of Terraform. If you run `terraform destroy` first, the EKS cluster
> is gone but those orphaned resources block VPC deletion. Always clean up in this order:

# 1. Delete ArgoCD app (removes Gateway → deletes Envoy Gateway NLB)
```bash
kubectl delete -f argocd/application.yml
```
# 2. Destroy infrastructure
```bash
cd terraform
terraform destroy -var-file=envs/dev.tfvars
```

**If `terraform destroy` gets stuck on LB deletion**, orphaned resources remain:
```bash
# Verify no Load Balancers remain in the VPC
aws elb describe-load-balancers --region us-west-2 \
  --query 'LoadBalancerDescriptions[*].LoadBalancerName' --output text

#Should be empty. If not, delete manually:
aws elb delete-load-balancer --load-balancer-name <name> --region us-west-2
```

**If `terraform destroy` gets stuck on VPC deletion**, orphaned resources remain:
```bash
# Find VPC
VPC_ID=$(aws ec2 describe-internet-gateways \
  --internet-gateway-ids <SG_ID> \
  --query 'InternetGateways[].Attachments[].VpcId' \
  --output text)
echo "VPC: $VPC_ID"

# Find and delete orphaned security groups
aws ec2 describe-security-groups --region us-west-2 \
  --filters Name=vpc-id,Values=$VPC_ID \
  --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' --output table
aws ec2 delete-security-group --group-id <SG_ID> --region us-west-2

# Then delete the VPC manually
aws ec2 delete-vpc --vpc-id $VPC_ID --region us-west-2

# Re-run terraform destroy to clean the state
terraform destroy
```
# 3. Destroy infrastructure backend-bootstrap

```bash
cd terraform/bootstrap
terraform destroy 
```
---

## Gotchas We Hit

### 1. Bug Report: Upstream Connection Timeout Error
**Symptom:** upstream connect error or disconnect/reset before headers. reset reason: connection timeout
**Cause:** The upstream server took too long to respond, causing the network proxy to time out and drop the connection.
**Fix:**
```bash
kubectl get deployments -n envoy-gateway-system
kubectl rollout restart deployment/envoy-skillpulse-skillpulse-gateway-41ed7599 -n envoy-gateway-system
kubectl rollout restart deployment/envoy-gateway -n envoy-gateway-system
```

### 2. `terraform destroy` Stuck on VPC Deletion
**Symptom:** `terraform destroy` hangs on VPC delete with `DependencyViolation`.
**Cause:** Helm-installed resources (Envoy Gateway, Grafana LB) created AWS Load Balancers and Security Groups outside Terraform. When EKS is destroyed first, these orphan and block VPC deletion.
**Fix:** Always uninstall Helm releases and delete the ArgoCD app BEFORE running `terraform destroy`. If already stuck, delete orphaned ELBs and SGs via AWS CLI (see Cleanup section above).

### 3. ArgoCD Shows OutOfSync After Manual Rollout Restart
**Symptom:** ArgoCD status shows `OutOfSync` even though app is healthy.
**Cause:** `kubectl rollout restart` adds a restartedAt annotation that doesn't match the Git manifest.
**Fix:** Not a problem — next CI push updates the manifest and ArgoCD syncs to it, resolving the drift.

---

## Access Summary

| Service | URL Command | Credentials |
|---------|------------|-------------|
| **skillpulse** | `kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=bankapp-gateway -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'` | App login |
| **ArgoCD** | `kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` | `admin` / see Step 3 |
| **Grafana** | `kubectl get svc kube-prometheus-grafana -n monitoring -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'` | `admin` / see Step 7 |