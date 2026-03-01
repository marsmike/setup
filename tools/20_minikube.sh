#!/bin/bash
# Phase 3 — Optional
# Installs minikube (local Kubernetes cluster).
set -euo pipefail

curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
rm minikube-linux-amd64

echo "minikube $(minikube version --short) installed."
