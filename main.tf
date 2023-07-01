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
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
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
    namespace = kubernetes_namespace_v1.pf1ns.metadata.0.name
  }
  spec {
    selector = {
      app = kubernetes_deployment_v1.promfiberdeploy.spec.0.template.0.metadata.0.labels.app
    }
    port {
      port        = 33000 # no effect in minikube, will forwarded to random port anyway
      target_port = kubernetes_deployment_v1.promfiberdeploy.spec.0.template.0.spec.0.container.0.port.0.container_port
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
          #security_context {
          #  run_as_group = "1000" # because /tmp/prom1data is owned by 1000
          #}
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
  # uninstall: https://keda.sh/docs/2.11/deploy/#helm
}
# run with this commented first, then uncomment
# from: https://www.youtube.com/watch?v=1kEKrhYMf_g
resource "kubernetes_manifest" "scaled_object" {
  manifest = {
    "apiVersion" = "keda.sh/v1alpha1"
    "kind"       = "ScaledObject"
    "metadata"   = {
      "name"      = "pf1scaledobject"
      "namespace" = kubernetes_namespace_v1.pf1ns.metadata.0.name
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