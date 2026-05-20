resource "helm_release" "kube_prometheus" {
  name             = "kube-prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "65.5.0" # pick the version you want
  namespace        = "monitoring"
  create_namespace = true
  wait             = true

  values = [yamlencode({
    grafana = {
      service = {
        type = "LoadBalancer" # same as --set grafana.service.type=LoadBalancer
      }
    }
  })]

  depends_on = [module.eks]
}