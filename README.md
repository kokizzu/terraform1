
# Terraform+Kubernetes+KEDA+Prometheus Example

this is example how to do stateless pod autoscaling with KEDA, Kubernetes, Prometheus and 
Terraform

Blog post: https://kokizzu.blogspot.com/2023/07/keda-kubernetes-event-driven-autoscaling.html

- main.tf - creates namespace, deployment, service, prometheus, keda, scaled object on kubernetes
- promfiber.go - service that we want to deploy and to be autoscaled when there's high request
- Dockerfile - container description to build promfiber.go
- debug-pod.yml - kubernetes manifest file to debug connectivity inside kubernetes cluster
