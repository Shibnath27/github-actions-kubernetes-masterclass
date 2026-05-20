resource "kubernetes_namespace_v1" "cert_manager" {
  metadata {
    name = "cert-manager"
  }
  provider   = kubernetes
  depends_on = [module.eks, null_resource.update_kubeconfig]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "oci://quay.io/jetstack/charts"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = false # Terraform already created it
  wait             = true

  values = [yamlencode({
    crds = {
      enabled = true
    }
    config = {
      enableGatewayAPI = true
    }
  })]

  depends_on = [
    kubernetes_namespace_v1.cert_manager,
  ]
}