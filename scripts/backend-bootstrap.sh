#!/bin/bash

set -e

# ==========================================
# Terraform Backend Bootstrap Utility
# ==========================================

echo "=========================================="
echo " Terraform Backend Bootstrap Utility"
echo "=========================================="
echo ""
echo "1) Create Backend Infrastructure"
echo "2) Destroy Backend Infrastructure"
echo ""

read -p "Choose option [1-2]: " OPTION

cd terraform/bootstrap


case $OPTION in

  1)
    echo ""
    echo "=========================================="
    echo " Creating S3 + DynamoDB Backend"
    echo "=========================================="
    
    terraform init
    terraform plan
    terraform apply -auto-approve

    echo ""
    echo "=========================================="
    echo " Backend Infrastructure Created"
    echo "=========================================="
    ;;

  2)
    echo ""
    echo "=========================================="
    echo " Destroying Backend Infrastructure"
    echo "=========================================="

    terraform destroy -auto-approve

    echo ""
    echo "=========================================="
    echo " Backend Infrastructure Destroyed"
    echo "=========================================="
    ;;

  *)
    echo ""
    echo "Invalid option selected"
    exit 1
    ;;

esac