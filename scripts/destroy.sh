#!/bin/bash

set -euo pipefail

# ======================================
# SkillPulse EKS Destroy Script
# ======================================

echo "======================================="
echo "     SkillPulse Destroy Utility"
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

# ======================================
# STEP 1 - GO TO TERRAFORM
# ======================================

cd terraform

# ======================================
# STEP 2 - SELECT WORKSPACE
# ======================================

echo ""
echo "======================================="
echo "STEP 2 - Select Workspace"
echo "======================================="

terraform workspace select $ENV

# ======================================
# STEP 3 - DELETE ARGOCD APP
# ======================================

echo ""
echo "======================================="
echo "STEP 3 - Delete ArgoCD Application"
echo "======================================="

kubectl delete -f ../argocd/application.yml --ignore-not-found=true || true

echo ""
echo "Waiting 60 seconds for Gateway / LoadBalancer cleanup..."
sleep 60

# ======================================
# STEP 4 - DELETE K8S RESOURCES
# ======================================

echo ""
echo "======================================="
echo "STEP 4 - Delete Kubernetes Resources"
echo "======================================="

cd ../k8s

FILES=(
  "80-backup.yaml"
  "70-cert-manager.yml"
  "60-gateway.yml"
  "50-hpa.yml"
  "40-frontend.yaml"
  "30-backend.yaml"
  "20-mysql.yaml"
  "10-secrets-sa.yaml"
  "00-namespace.yaml"
)

for file in "${FILES[@]}"
do
  if [ -f "$file" ]; then
    echo ""
    echo "Deleting $file ..."
    kubectl delete -f $file --ignore-not-found=true || true
  fi
done

cd ../terraform

echo ""
echo "Waiting 60 seconds for Kubernetes resources cleanup..."
sleep 60

# ======================================
# STEP 5 - TERRAFORM DESTROY
# ======================================

echo ""
echo "======================================="
echo "STEP 5 - Terraform Destroy"
echo "======================================="

terraform destroy \
  -var-file="envs/${ENV}.tfvars" \
  -auto-approve

# ======================================
# STEP 6 - CLEAN ORPHAN LOAD BALANCERS
# ======================================

echo ""
echo "======================================="
echo "STEP 6 - Check Orphan LoadBalancers"
echo "======================================="

# ── Orphaned Load Balancers ───────────────────────────────────────────────
 
  # Verify no classic LBs remain
  aws elb describe-load-balancers \
    --region $REGION \
    --query 'LoadBalancerDescriptions[*].LoadBalancerName' \
    --output text
 
  for LB_NAME in $(aws elb describe-load-balancers \
    --region $REGION \
    --query 'LoadBalancerDescriptions[*].LoadBalancerName' \
    --output text 2>/dev/null); do
    warn "Deleting classic ELB: $LB_NAME"
    aws elb delete-load-balancer \
      --load-balancer-name "$LB_NAME" \
      --region $REGION
  done
 
  for ARN in $(aws elbv2 describe-load-balancers \
    --region $REGION \
    --query 'LoadBalancers[*].LoadBalancerArn' \
    --output text 2>/dev/null); do
    warn "Deleting ELBv2: $ARN"
    aws elbv2 delete-load-balancer --load-balancer-arn "$ARN" --region $REGION
  done
 
  [ -n "$(aws elb describe-load-balancers --region $REGION \
    --query 'LoadBalancerDescriptions[*].LoadBalancerName' \
    --output text 2>/dev/null)" ] && sleep 30 || true
 
  # ── Orphaned VPC resources ────────────────────────────────────────────────
echo ""
echo "---------------------------------------"
echo "Checking orphaned VPC resources..."
echo "---------------------------------------"
 
  for IGW_ID in $(aws ec2 describe-internet-gateways \
    --region $REGION \
    --query 'InternetGateways[].InternetGatewayId' \
    --output text 2>/dev/null); do
 
    VPC_ID=$(aws ec2 describe-internet-gateways \
      --region $REGION \
      --internet-gateway-ids "$IGW_ID" \
      --query 'InternetGateways[].Attachments[].VpcId' \
      --output text 2>/dev/null)
 
    [ -z "$VPC_ID" ] && continue
    echo "VPC: $VPC_ID"
 
    # List + delete orphaned security groups
    aws ec2 describe-security-groups \
      --region $REGION \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'SecurityGroups[?GroupName!=`default`].[GroupId,GroupName]' \
      --output table
 
    for SG_ID in $(aws ec2 describe-security-groups \
      --region $REGION \
      --filters "Name=vpc-id,Values=$VPC_ID" \
      --query 'SecurityGroups[?GroupName!=`default`].GroupId' \
      --output text 2>/dev/null); do
      warn "Deleting SG: $SG_ID"
      aws ec2 delete-security-group \
        --group-id "$SG_ID" --region $REGION 2>/dev/null || true
    done
 
    # Detach + delete IGW
    warn "Detaching IGW: $IGW_ID"
    aws ec2 detach-internet-gateway \
      --internet-gateway-id "$IGW_ID" \
      --vpc-id "$VPC_ID" --region $REGION 2>/dev/null || true
    aws ec2 delete-internet-gateway \
      --internet-gateway-id "$IGW_ID" --region $REGION 2>/dev/null || true
 
    # Delete VPC manually
    warn "Deleting VPC: $VPC_ID"
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region $REGION \
      && log "VPC $VPC_ID deleted" \
      || warn "VPC still has dependencies — check AWS console"
  done
 
  # Re-run terraform destroy to clean remaining state
  echo ""
  info "Re-running terraform destroy to clean state..."
  terraform destroy -var-file="$TFVARS" -auto-approve || \
    warn "Some resources may need manual cleanup in the AWS console"

 
cd "$REPO_ROOT"

# ======================================
# COMPLETE
# ======================================

echo ""
echo "======================================="
echo "SkillPulse Infrastructure Destroyed"
echo "Environment : $ENV"
echo "======================================="