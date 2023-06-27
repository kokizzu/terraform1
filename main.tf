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
    path = "/tmp/pf1.tfstate"
  }
}
provider "kubernetes" {
  config_path    = "~/.kube/config"
  # from k config view | grep -A 3 minikube | grep server:
  host           = "https://192.168.59.100:8443"
  config_context = "minikube"
}
provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "minikube"
  }
}
resource "kubernetes_namespace_v1" "pf1ns" {
  metadata {
    name        = "pf1ns"
    annotations = {
      name = "deployment namespace"
    }
  }
}
resource "kubernetes_deployment_v1" "pf1deploy" {
  metadata {
    name      = "pf1deploy"
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
  }
  spec {
    selector {
      match_labels = {
        app = "pf1"
      }
    }
    replicas = "1"
    template {
      metadata {
        labels = {
          app = "pf1"
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
          image = "kokizzu/pf1"
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
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment_v1.pf1deploy.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 33000 # no effect in minikube, will forwarded to random port anyway
      target_port = kubernetes_deployment_v1.pf1deploy.spec.0.template.0.spec.0.container.0.port.0.container_port
    }
    type = "NodePort"
  }
}
resource "kubernetes_ingress_v1" "pf1ingress" {
  metadata {
    name        = "pf1ingress"
    namespace   = kubernetes_namespace_v1.pf1ns.metadata.0.name
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
resource "kubernetes_config_map_v1" "prom1conf" {
  metadata {
    name      = "prom1conf"
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
  }
  data = {
    # from https://github.com/techiescamp/kubernetes-prometheus/blob/master/config-map.yaml
    "prometheus.yml" : <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
alerting:
  alertmanagers:
    - static_configs:
        - targets:
          # - alertmanager:9093
rule_files:
  #- /etc/prometheus/prometheus.rules
scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
  - job_name: "pf1"
    static_configs:
      - targets: [
          "${kubernetes_ingress_v1.pf1ingress.spec.0.rule.0.host}:${kubernetes_service_v1.pf1svc.spec.0.port.0.port}"
        ]
EOF
    # need to delete stateful set if this changed after terraform apply
    # or kubectl rollout restart statefulset prom1stateful -n pf1ns
    # because statefulset pod not restarted automatically when changed
    # if configmap set as env or config file
  }
}
resource "kubernetes_persistent_volume_v1" "prom1datavol" {
  metadata {
    name = "prom1datavol"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    capacity     = {
      storage = "1Gi"
    }
    # do not add storage_class_name or it would stuck
    persistent_volume_source {
      host_path {
        path = "/tmp/prom1data" # mkdir first?
      }
    }
  }
}
resource "kubernetes_persistent_volume_claim_v1" "prom1dataclaim" {
  metadata {
    name      = "prom1dataclaim"
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
  }
  spec {
    # do not add storage_class_name or it would stuck
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
resource "kubernetes_stateful_set_v1" "prom1stateful" {
  metadata {
    name      = "prom1stateful"
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
    labels    = {
      app = "prom1"
    }
  }
  spec {
    selector {
      match_labels = {
        app = "prom1"
      }
    }
    template {
      metadata {
        labels = {
          app = "prom1"
        }
      }
      # example: https://github.com/mateothegreat/terraform-kubernetes-monitoring-prometheus/blob/main/deployment.tf
      spec {
        container {
          name  = "prometheus"
          image = "prom/prometheus:latest"
          args  = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus/",
            "--web.console.libraries=/etc/prometheus/console_libraries",
            "--web.console.templates=/etc/prometheus/consoles",
            "--web.enable-lifecycle",
            "--web.enable-admin-api",
            "--web.listen-address=:10902"
          ]
          port {
            name           = "http1"
            container_port = 10902
          }
          volume_mount {
            name       = kubernetes_config_map_v1.prom1conf.metadata.0.name
            mount_path = "/etc/prometheus/"
          }
          volume_mount {
            name       = "prom1datastorage"
            mount_path = "/prometheus/"
          }
          #          security_context {
          #            run_as_group = "1000" # because /tmp/prom1data is owned by 1000
          #          }
        }
        volume {
          name = kubernetes_config_map_v1.prom1conf.metadata.0.name
          config_map {
            default_mode = "0666"
            name         = kubernetes_config_map_v1.prom1conf.metadata.0.name
          }
        }
        volume {
          name = "prom1datastorage"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.prom1dataclaim.metadata.0.name
          }
        }
      }
    }
    service_name = ""
  }
}
resource "kubernetes_service_v1" "prom1svc" {
  metadata {
    name      = "prom1svc"
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_stateful_set_v1.prom1stateful.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 10902 # no effect in minikube, will forwarded to random port anyway
      target_port = kubernetes_stateful_set_v1.prom1stateful.spec.0.template.0.spec.0.container.0.port.0.container_port
    }
    type = "NodePort"
  }
}
resource "helm_release" "pf1keda" {
  name       = "pf1keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  namespace  = kubernetes_namespace_v1.pf1ns.metadata.0.name
  # uninstall: https://keda.sh/docs/2.10/deploy/#helm
}
# from: https://www.youtube.com/watch?v=1kEKrhYMf_g
resource "kubernetes_manifest" "scaled_object" {
  manifest = {
    "apiVersion" = "keda.sh/v1alpha1"
    "kind"       = "ScaledObject"
    "metadata"   = {
      "name"      = "pf1keda"
      "namespace" = kubernetes_namespace_v1.pf1ns.metadata.0.name
    }
    "spec" = {
      "scaleTargetRef" = {
        "apiVersion" = "apps/v1"
        "name"       = kubernetes_deployment_v1.pf1deploy.metadata.0.name
        "kind"       = "Deployment"
      }
      "minReplicaCount" = 1
      "maxReplicaCount" = 5
      "triggers"        = [
        {
          "type"     = "prometheus"
          "metadata" = {
            "serverAddress" = "http://prom1svc.pf1ns.svc.cluster.local:10902"
            "threshold"     = "10"
            "query"         = "sum(rate(http_requests_total{kubernetes_namespace=\"pf1ns\"}[1m]))"
          }
        }
      ]
    }
  }
}

# failed attempt:
#resource "kubernetes_config_map_v1" "pf1adapterconf" {
#  metadata {
#    name      = "pf1adapterconf"
#    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
#  }
#  data = {
#    "config.yaml" : <<EOF
#rules:
#- seriesQuery: 'http_requests_total{kubernetes_namespace="pf1ns"}'
#  resources:
#    overrides:
#      kubernetes_namespace: {resource: "namespace"}
#      kubernetes_pod_name: {resource: "pod"}
#  name:
#    matches: "^(.*)_total"
#    as: "${1}_per_second"
#  metricsQuery: 'sum(rate(<<.Series>>{<<.LabelMatchers>>}[1m])) by (<<.GroupBy>>)'
#EOF
#  }
#}
#resource "kubernetes_deployment_v1" "pf1custommetricapi" {
#  metadata {
#    name      = "pf1custommetricapi"
#    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
#  }
#  spec {
#    replicas = "1"
#    selector {
#      match_labels = {
#        app = "pf1custommetricapi"
#      }
#    }
#    template {
#      metadata {
#        labels = {
#          app = "pf1custommetricapi"
#        }
#        name = "pf1custommetricapi"
#      }
#      spec {
#        #service_account_name = "monitoring"
#        # https://github.com/kubernetes-sigs/prometheus-adapter
#        container {
#          name  = "pf1custommetricapi"
#          image = "quay.io/coreos/k8s-prometheus-adapter-amd64:v0.8.4"
#          args  = [
#            "/adapter",
#            "--logtostderr=true",
#            "--prometheus-url=http://${kubernetes_ingress_v1.pf1ingress.spec.0.rule.0.host}:${kubernetes_service_v1.prom1svc.spec.0.port.0.port}/metrics",
#            "--metrics-relist-interval=1m",
#            "--v=10",
#            "--config=/etc/adapter/config.yaml",
#            "--cert-dir=/tmp"
#          ]
#          port {
#            container_port = 443
#          }
#          volume_mount {
#            mount_path = "/etc/adapter"
#            name       = "pf1adapterconfstorage"
#            read_only  = true
#          }
#        }
#        volume {
#          name = "pf1adapterconfstorage"
#          config_map {
#            name = kubernetes_config_map_v1.pf1adapterconf.metadata.0.name
#          }
#        }
#      }
#    }
#  }
#}
#resource "kubernetes_horizontal_pod_autoscaler_v2" "pf1autoscale" {
#  metadata {
#    name      = "pf1autoscale"
#    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
#  }
#  spec {
#    max_replicas = 5
#    min_replicas = 1
#    scale_target_ref {
#      api_version = "apps/v1"
#      kind        = "Deployment"
#      name        = kubernetes_deployment_v1.pf1deploy.metadata.0.name
#    }
#    metric {
#      type = "Pods"
#      pods {
#        metric {
#          name = "http_requests"
#        }
#        target {
#          type          = "Value"
#          average_value = 1000
#        }
#      }
#    }
#  }
#
#}
