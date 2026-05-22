#!/bin/bash

set -euo pipefail

# ================================
# SkillPulse EKS Deployment Script
# ================================

echo "======================================="
echo "   SkillPulse Multi-Env Deployment"
echo "======================================="
echo ""
echo "Choose Environment:"
echo "1) dev"
echo "2) staging"
echo "3) prod"
echo ""

read -p "Enter option [1-3]: " OPTION

case $OPTION in
  1)
    ENV="dev"
    ;;
  2)
    ENV="staging"
    ;;
  3)
    ENV="prod"
    ;;
  *)
    echo "Invalid option"
    exit 1
    ;;
esac

echo ""
echo "Selected Environment: $ENV"
echo ""

# ================================
# STEP 2 - TERRAFORM INIT
# ================================

echo ""
echo "======================================="
echo "STEP 1 - Terraform Init"
echo "======================================="

cd terraform
terraform init -reconfigure

# ================================
# STEP 2 - CREATE WORKSPACES
# ================================

echo ""
echo "======================================="
echo "STEP 2 - Ensure Terraform Workspaces"
echo "======================================="

terraform workspace new dev || true
terraform workspace new staging || true
terraform workspace new prod || true

# ================================
# STEP 3 - SELECT WORKSPACE
# ================================

echo ""
echo "======================================="
echo "STEP 3 - Select Workspace"
echo "======================================="

terraform workspace select $ENV

# ================================
# STEP 4 - TERRAFORM PLAN
# ================================

echo ""
echo "======================================="
echo "STEP 4 - Terraform Plan"
echo "======================================="

terraform plan \
  -var-file="envs/${ENV}.tfvars"

# ================================
# STEP 5 - TERRAFORM APPLY
# ================================

echo ""
echo "======================================="
echo "STEP 5 - Terraform Apply"
echo "======================================="

terraform apply \
  -var-file="envs/${ENV}.tfvars" \
  -auto-approve

# ================================
# STEP 6 - UPDATE KUBECONFIG
# ================================

echo ""
echo "======================================="
echo "STEP 6 - Update kubeconfig"
echo "======================================="

KUBECTL_CMD=$(terraform output -raw configure_kubectl)
echo "Running: $KUBECTL_CMD"
eval "$KUBECTL_CMD"

# ================================
# STEP 7 - VERIFY CLUSTER
# ================================

echo ""
echo "======================================="
echo "STEP 7 - Verify Cluster"
echo "======================================="

kubectl get nodes
kubectl get pods -n argocd

# ================================
# STEP 8 - APPLY K8S MANIFESTS
# ================================

echo ""
echo "======================================="
echo "STEP 8 - Apply Kubernetes Manifests"
echo "======================================="

cd ../k8s

FILES=(
  "00-namespace.yaml"
  "10-secrets-sa.yaml"
  "20-mysql.yaml"
  "30-backend.yaml"
  "40-frontend.yaml"
  "50-hpa.yml"
  "60-gateway.yml"
  "70-cert-manager.yml"
  "80-backup.yaml"
)

for file in "${FILES[@]}"
do
  if [ -f "$file" ]; then
    echo ""
    echo "Applying $file ..."
    kubectl apply -f $file
  fi
done

# ================================
# STEP 9 - WAIT
# ================================

echo ""
echo "======================================="
echo "STEP 9 - Wait For Pods"
echo "======================================="

kubectl wait --for=condition=Ready pods --all -n skillpulse --timeout=600s || true
kubectl get gatewayclass
kubectl get pods -n cert-manager
kubectl get pods -n skillpulse
# ================================
# STEP 10 - APPLY ARGOCD APP
# ================================

echo ""
echo "======================================="
echo "STEP 10 - Apply ArgoCD Application"
echo "======================================="

kubectl apply -f ../argocd/application.yml

# ================================
# STEP 11 - SHOW STATUS
# ================================

echo ""
echo "======================================="
echo "Deployment Completed Successfully"
echo "======================================="

echo ""
kubectl get pods -n skillpulse

echo ""
kubectl get svc -n skillpulse

echo ""
kubectl get gateway -n skillpulse || true

echo ""
echo "======================================="
echo "SkillPulse Deployment Successful"
echo "Environment : $ENV"
echo "======================================="
echo ""
echo "======================================="
echo "Get Grafana URL"
kubectl get svc kube-prometheus-grafana -n monitoring \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""
echo "Get Grafana password"
kubectl get secret kube-prometheus-grafana -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
echo "======================================="
echo ""
echo "======================================="
echo "Get ArgoCD URL"
kubectl get svc argocd-server -n argocd \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
echo ""
echo "Get ArgoCD password"
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d; echo
echo "======================================="