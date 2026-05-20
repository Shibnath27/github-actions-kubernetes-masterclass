# AWS Provider (HELM WAY - SIMPLER)
resource "helm_release" "secrets_store_aws_provider" {
  name       = "secrets-provider-aws"
  repository = "https://aws.github.io/secrets-store-csi-driver-provider-aws"
  chart      = "secrets-store-csi-driver-provider-aws"
  namespace  = "kube-system"
  set {
    name  = "aws.region"
    value = var.aws_region # e.g., "us-west-2"
  }
  set {
    name  = "secrets-store-csi-driver.install"
    value = "true"
  }
  set {
    name  = "secrets-store-csi-driver.enableSecretRotation"
    value = "true"
  }
  set {
    name  = "secrets-store-csi-driver.syncSecret.enabled"
    value = "true"
  }
  depends_on = [module.eks]
}

# IAM POLICY
resource "aws_iam_policy" "secrets_policy" {
  name = "${local.environment}-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "*"
    }]
  })
}

# IRSA ROLE
module "secrets_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "~> 5.0"

  create_role = true

  role_name = "secrets-role"

  provider_url = module.eks.oidc_provider

  role_policy_arns = [
    aws_iam_policy.secrets_policy.arn,
    aws_iam_policy.mysql_backup.arn
  ]

  oidc_fully_qualified_subjects = ["system:serviceaccount:${var.namespace}:secrets-sa"]
}
