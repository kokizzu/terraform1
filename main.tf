# main.tf
terraform {
  required_version = ">= 1.3.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.20.0"
    }
  }
  backend "local" {
    path = "./pf1.tfstate"
  }
}
variable "nsname" {
  default = "pf1ns"
}
provider "kubernetes" {
  config_path    = "~/.kube/config"
  # from: k config view | grep -A 3 minikube | grep server:
  host           = "https://240.1.0.2:8443"
  config_context = "minikube"
}
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}
resource "kubernetes_namespace_v1" "pf1ns" {
  # if already created: terraform import kubernetes_namespace_v1.pf1ns pf1ns
  metadata {
    name        = "pf1ns"
    annotations = {
      name = "deployment namespace"
    }
  }
}
resource "kubernetes_deployment_v1" "promfiberdeploy" {
  metadata {
    name      = "promfiberdeploy"
    namespace = var.nsname
  }
  spec {
    selector {
      match_labels = {
        app = "promfiber"
      }
    }
    replicas = "1"
    template {
      metadata {
        labels = {
          app = "promfiber"
        }
        annotations = {
          "prometheus.io/path"   = "/metrics"
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = 3000
        }
      }
      spec {
        container {
          name  = "pf1"
          image = "kokizzu/pf1:v0001" # from promfiber.go
          port {
            container_port = 3000
          }
        }
      }
    }
  }
}
resource "kubernetes_service_v1" "pf1svc" {
  metadata {
    name      = "pf1svc"
    namespace = var.nsname
  }
  spec {
    selector = {
      app = kubernetes_deployment_v1.promfiberdeploy.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 3001
      node_port   = 32000
      target_port = kubernetes_deployment_v1.promfiberdeploy.spec.0.template.0.spec.0.container.0.port.0.container_port
    }
    type = "NodePort"
  }
}
resource "kubernetes_ingress_v1" "pf1ingress" {
  metadata {
    name        = "pf1ingress"
    namespace   = var.nsname
    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }
  spec {
    rule {
      host = "pf1svc.pf1ns.svc.cluster.local"
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service_v1.pf1svc.metadata.0.name
              port {
                number = kubernetes_service_v1.pf1svc.spec.0.port.0.port
              }
            }
          }
        }
      }
    }
  }
}
## without operator, if there's multiple pod only one getting fetched by prometheus
#resource "kubernetes_config_map_v1" "prom1conf" {
#  metadata {
#    name      = "prom1conf"
#    namespace = var.nsname
#  }
#  data = {
#    # from https://github.com/techiescamp/kubernetes-prometheus/blob/master/config-map.yaml
#    "prometheus.yml" : <<EOF
#global:
#  scrape_interval: 15s
#  evaluation_interval: 15s
#alerting:
#  alertmanagers:
#    - static_configs:
#        - targets:
#          # - alertmanager:9093
#rule_files:
#  #- /etc/prometheus/prometheus.rules
#scrape_configs:
#  - job_name: "prometheus"
#    static_configs:
#      - targets: ["localhost:9090"]
#  - job_name: "pf1"
#    static_configs:
#      - targets: [
#          "${kubernetes_ingress_v1.pf1ingress.spec.0.rule.0.host}:${kubernetes_service_v1.pf1svc.spec.0.port.0.port}"
#        ]
#EOF
#    # need to delete stateful set if this changed after terraform apply
#    # or kubectl rollout restart statefulset prom1stateful -n pf1ns
#    # because statefulset pod not restarted automatically when changed
#    # if configmap set as env or config file
#  }
#}
#resource "kubernetes_persistent_volume_v1" "prom1datavol" {
#  metadata {
#    name = "prom1datavol"
#  }
#  spec {
#    access_modes = ["ReadWriteOnce"]
#    capacity     = {
#      storage = "1Gi"
#    }
#    # do not add storage_class_name or it would stuck
#    persistent_volume_source {
#      host_path {
#        path = "/tmp/prom1data" # mkdir first?
#      }
#    }
#  }
#}
#resource "kubernetes_persistent_volume_claim_v1" "prom1dataclaim" {
#  metadata {
#    name      = "prom1dataclaim"
#    namespace = var.nsname
#  }
#  spec {
#    # do not add storage_class_name or it would stuck
#    access_modes = ["ReadWriteOnce"]
#    resources {
#      requests = {
#        storage = "1Gi"
#      }
#    }
#  }
#}
#resource "kubernetes_stateful_set_v1" "prom1stateful" {
#  metadata {
#    name      = "prom1stateful"
#    namespace = var.nsname
#    labels    = {
#      app = "prom1"
#    }
#  }
#  spec {
#    selector {
#      match_labels = {
#        app = "prom1"
#      }
#    }
#    template {
#      metadata {
#        labels = {
#          app = "prom1"
#        }
#      }
#      # example: https://github.com/mateothegreat/terraform-kubernetes-monitoring-prometheus/blob/main/deployment.tf
#      spec {
#        container {
#          name  = "prometheus"
#          image = "prom/prometheus:latest"
#          args  = [
#            "--config.file=/etc/prometheus/prometheus.yml",
#            "--storage.tsdb.path=/prometheus/",
#            "--web.console.libraries=/etc/prometheus/console_libraries",
#            "--web.console.templates=/etc/prometheus/consoles",
#            "--web.enable-lifecycle",
#            "--web.enable-admin-api",
#            "--web.listen-address=:10902"
#          ]
#          port {
#            name           = "http1"
#            container_port = 10902
#          }
#          volume_mount {
#            name       = kubernetes_config_map_v1.prom1conf.metadata.0.name
#            mount_path = "/etc/prometheus/"
#          }
#          volume_mount {
#            name       = "prom1datastorage"
#            mount_path = "/prometheus/"
#          }
#          #security_context {
#          #  run_as_group = "1000" # because /tmp/prom1data is owned by 1000
#          #}
#        }
#        volume {
#          name = kubernetes_config_map_v1.prom1conf.metadata.0.name
#          config_map {
#            default_mode = "0666"
#            name         = kubernetes_config_map_v1.prom1conf.metadata.0.name
#          }
#        }
#        volume {
#          name = "prom1datastorage"
#          persistent_volume_claim {
#            claim_name = kubernetes_persistent_volume_claim_v1.prom1dataclaim.metadata.0.name
#          }
#        }
#      }
#    }
#    service_name = ""
#  }
#}
#resource "kubernetes_service_v1" "prom1svc" {
#  metadata {
#    name      = "prom1svc"
#    namespace = var.nsname
#  }
#  spec {
#    selector = {
#      app = kubernetes_stateful_set_v1.prom1stateful.spec.0.template.0.metadata.0.labels.app
#    }
#    port {
#      port        = 10902 # no effect in minikube, will forwarded to random port anyway
#      target_port = kubernetes_stateful_set_v1.prom1stateful.spec.0.template.0.spec.0.container.0.port.0.container_port
#    }
#    type = "NodePort"
#  }
#}
# operator version, solves multiple instance of pod issue
# manually:
# helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
# helm search repo prometheus-community
# helm install globalprom prometheus-community/kube-prometheus-stack -n default
# will automatically create node exporter grafana and all others
resource "helm_release" "globalprom" {
  name       = "globalprom"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "default"
  # uninstall: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#kube-prometheus-stack
}
resource "kubernetes_service_v1" "globalpromsvc" {
  metadata {
    name      = "globalpromsvc"
    namespace = helm_release.globalprom.namespace
  }
  spec {
    selector = {
      "app.kubernetes.io/name" = "prometheus" # default for prometheus operator
    }
    port {
      target_port = 9090 # default port for prometheus-pf1prom-kube-prometheus-st-prometheus-0 pod
      port        = 9091
      node_port   = 30900
    }
    type = "NodePort"
  }
}
resource "kubernetes_service_account_v1" "pf1promsvcacc" {
  metadata {
    name      = "pf1promsvcacc"
    namespace = var.nsname
  }
}
resource "kubernetes_cluster_role_v1" "promrole" {
  metadata {
    name = "promrole"
  }
  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "pods"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["extensions"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch"]
  }
}
resource "kubernetes_cluster_role_binding_v1" "pf1promsvcrole" {
  metadata {
    name = "pf1promsvcrole"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.promrole.metadata.0.name
  }
  subject {
    kind = "ServiceAccount"
    name = kubernetes_service_account_v1.pf1promsvcacc.metadata.0.name
  }
}
resource "kubernetes_manifest" "pf1prompodmonitor" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "PodMonitor"
    "metadata"   = {
      "name"      = "pf1prompodmonitor"
      "namespace" = var.nsname
      "labels"    = {
        "name" = "pf1podmonitor"
      }
    }
    "spec" = {
      "selector" = {
        "matchLabels" = {
          "app" = kubernetes_deployment_v1.promfiberdeploy.spec.0.selector.0.match_labels.app
        }
      }
      "namespaceSelector" = {
        "matchNames" = [
          var.nsname
        ]
      }
      "podMetricsEndpoints" = [
        {
          "interval" = "5s"
          "port"     = kubernetes_deployment_v1.promfiberdeploy.spec.0.template.0.spec.0.container.0.port.0.container_port
        }
      ]
    }
  }
}
# changing this requires rollout restart?
# kubectl rollout restart statefulset prometheus-pf1prom -n pf1ns
resource "kubernetes_manifest" "pf1prom" {
  manifest = {
    "apiVersion" = "monitoring.coreos.com/v1"
    "kind"       = "Prometheus"
    "metadata"   = {
      "name"      = "pf1prom"
      "namespace" = var.nsname
    }
    "spec" = {
      # if error check k get events -n pf1ns
      "serviceAccountName" = kubernetes_service_account_v1.pf1promsvcacc.metadata.0.name
      "podMonitorSelector" = {
        "matchLabels" = {
          "name" = kubernetes_manifest.pf1prompodmonitor.manifest.metadata.labels.name
        }
      }
      "resources" = {
        "requests" = {
          "memory" = "400Mi"
        }
      }
    }
  }
}
resource "kubernetes_service_v1" "pf1promsvc" {
  metadata {
    name      = "pf1promsvc"
    namespace = var.nsname
  }
  spec {
    selector = {
      "prometheus" = kubernetes_manifest.pf1prom.manifest.metadata.name
    }
    port {
      target_port = 9090 # default port for prometheus-pf1prom-0
      port        = 9092
      node_port   = 30901
    }
    type = "NodePort"
  }
}
resource "helm_release" "pf1keda" {
  name       = "pf1keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  namespace  = var.nsname
  # uninstall: https://keda.sh/docs/2.11/deploy/#helm
}
# run with this commented first, then uncomment
# or helm install manually pf1keda kedacore/keda
# since by default scaledobject not there in: kubectl api-resources
# from: https://www.youtube.com/watch?v=1kEKrhYMf_g
resource "kubernetes_manifest" "pf1kedascaledobject" {
  manifest = {
    "apiVersion" = "keda.sh/v1alpha1" # error "cannot select exact GV from REST mapper" if wrong
    "kind"       = "ScaledObject"
    "metadata"   = {
      "name"      = "pf1kedascaledobject"
      "namespace" = var.nsname
    }
    "spec" = {
      "scaleTargetRef" = {
        "apiVersion" = "apps/v1"
        "name"       = kubernetes_deployment_v1.promfiberdeploy.metadata.0.name
        "kind"       = "Deployment"
      }
      "minReplicaCount" = 1
      "maxReplicaCount" = 5
      "triggers"        = [
        {
          "type"     = "prometheus"
          "metadata" = {
            "serverAddress" = "http://prom1svc.pf1ns.svc.cluster.local:10902"
            "threshold"     = "100"
            "query"         = "sum(irate(http_requests_total[1m]))"
            # with or without {service=\"promfiber\"} is the same since 1 service 1 pod in our case
          }
        }
      ]
    }
  }
}