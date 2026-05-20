resource "null_resource" "update_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${local.region}"
  }

  depends_on = [module.eks]
}

# Step 1: Gateway API CRDs (apply once, outside Helm)
data "http" "gateway_api_standard" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
}

locals {
  gateway_api_crds = [
    for m in split("---", data.http.gateway_api_standard.response_body) :
    m if trimspace(m) != "" && can(yamldecode(m)) && lookup(yamldecode(m), "kind", "") != ""
  ]
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each   = { for idx, m in local.gateway_api_crds : idx => m }
  yaml_body  = each.value
  depends_on = [null_resource.update_kubeconfig]
}


# Step 2: Envoy Gateway Helm chart
resource "helm_release" "envoy_gateway" {
  name             = "eg"
  repository       = "oci://docker.io/envoyproxy"
  chart            = "gateway-helm"
  version          = "v1.2.6"
  namespace        = "envoy-gateway-system"
  create_namespace = true

  # Important: skip CRDs because we applied Gateway API CRDs separately
  skip_crds = true

  # Wait for resources to be ready
  wait       = true
  timeout    = 300
  depends_on = [kubectl_manifest.gateway_api_crds]
}

# Step 3: Envoy Gateway extension CRDs
resource "null_resource" "envoy_gateway_crds" {
  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/eg-chart
      helm pull oci://docker.io/envoyproxy/gateway-helm --version v1.2.6 --untar -d /tmp/eg-chart
      kubectl apply --server-side -f /tmp/eg-chart/gateway-helm/crds/generated/
    EOT
  }
  depends_on = [kubectl_manifest.gateway_api_crds]
}

resource "null_resource" "envoy_gateway_rollout" {
  provisioner "local-exec" {
    command = <<EOT
      kubectl rollout restart deployment envoy-gateway -n envoy-gateway-system || true
    EOT
  }
  depends_on = [helm_release.envoy_gateway, helm_release.secrets_store_aws_provider]
}