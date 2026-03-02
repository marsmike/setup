#!/bin/bash
# Phase 10 — Container & Kubernetes tools (macOS)
# Installs: ctop, dive, lazydocker, k9s, kubectl, helm, k3d, kind, minikube
set -euo pipefail

brew install \
  ctop \
  dive \
  lazydocker \
  k9s \
  kubectl \
  helm \
  k3d \
  kind \
  minikube

echo ""
echo "Container tools installed: ctop, dive, lazydocker, k9s, kubectl, helm, k3d, kind, minikube"
echo "NOTE: Docker Desktop must be installed manually from https://www.docker.com/products/docker-desktop/"
