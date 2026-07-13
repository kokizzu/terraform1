
# Terraform+Kubernetes+KEDA+Prometheus Example

this is example how to do stateless pod autoscaling with KEDA, Kubernetes, Prometheus and 
Terraform

Blog post: https://kokizzu.blogspot.com/2023/07/keda-kubernetes-event-driven-autoscaling.html

- main.tf - creates namespace, deployment, service, prometheus, keda, scaled object on kubernetes
- promfiber.go - service that we want to deploy and to be autoscaled when there's high request
- Dockerfile - container description to build promfiber.go
- debug-pod.yml - kubernetes manifest file to debug connectivity inside kubernetes cluster

## Maintenance checklist

- [x] Go runtime updated to 1.26.5.
- [x] Fiber Prometheus, Fiber, OpenTelemetry, and security-sensitive Go modules refreshed.
- [x] Terraform requirement updated to 1.15.8, Kubernetes provider to 3.2.1, and Helm provider to 3.2.0.
- [x] Kubernetes ingress config updated with `ingress_class_name` and `path_type`.
- [x] Go vendor directory regenerated after dependency updates.
- [x] `make test` runs Go tests and checks Terraform formatting when Terraform is installed.
- [x] `make verify-dependency-security` and `make vulncheck` check dependency security.
