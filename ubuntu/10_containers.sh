#!/bin/bash
# Container & Kubernetes tools
# Installs: ctop, dive, lazydocker, kubectl, helm, k3d, kind, minikube
set -euo pipefail

mkdir -p ~/.local/bin

# --- ctop ---
echo "Installing ctop..."
CTOP_VERSION=$(curl -sL "https://api.github.com/repos/bcicen/ctop/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/bcicen/ctop/releases/download/v${CTOP_VERSION}/ctop-${CTOP_VERSION}-linux-amd64" \
  -o "$TMP/ctop"
install "$TMP/ctop" ~/.local/bin/ctop
trap - EXIT; rm -rf "$TMP"
echo "ctop v${CTOP_VERSION} installed."

# --- dive (needs dpkg → sudo) ---
echo "Installing dive..."
DIVE_VERSION=$(curl -sL "https://api.github.com/repos/wagoodman/dive/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.deb" \
  -o "$TMP/dive.deb"
sudo dpkg -i "$TMP/dive.deb"
trap - EXIT; rm -rf "$TMP"
echo "dive v${DIVE_VERSION} installed."

# --- lazydocker ---
echo "Installing lazydocker..."
LAZYDOCKER_VER=$(curl -fsSL "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VER}/lazydocker_${LAZYDOCKER_VER}_Linux_x86_64.tar.gz" \
  | tar -xzf - -C "$TMP"
install "$TMP/lazydocker" ~/.local/bin/lazydocker
trap - EXIT; rm -rf "$TMP"
echo "lazydocker v${LAZYDOCKER_VER} installed."

# --- k9s ---
echo "Installing k9s..."
K9S_VER=$(curl -sL "https://api.github.com/repos/derailed/k9s/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://github.com/derailed/k9s/releases/download/v${K9S_VER}/k9s_Linux_amd64.tar.gz" \
  | tar -xzf - -C "$TMP"
install "$TMP/k9s" ~/.local/bin/k9s
trap - EXIT; rm -rf "$TMP"
echo "k9s v${K9S_VER} installed."

# --- kubectl ---
echo "Installing kubectl..."
KUBECTL_VER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VER}/bin/linux/amd64/kubectl" -o "$TMP/kubectl"
install "$TMP/kubectl" ~/.local/bin/kubectl
trap - EXIT; rm -rf "$TMP"
echo "kubectl ${KUBECTL_VER} installed."

# --- helm (official installer — uses sudo internally) ---
echo "Installing helm..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/get_helm.sh" https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 "$TMP/get_helm.sh"
"$TMP/get_helm.sh"
trap - EXIT; rm -rf "$TMP"
echo "helm $(helm version --short) installed."

# --- k3d (official installer) ---
echo "Installing k3d..."
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
echo "k3d $(k3d version) installed."

# --- kind ---
echo "Installing kind..."
KIND_VERSION=$(curl -sL "https://api.github.com/repos/kubernetes-sigs/kind/releases/latest" \
  | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
[ "$(uname -m)" = x86_64 ] && \
  curl -fsSL "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64" -o "$TMP/kind"
install "$TMP/kind" ~/.local/bin/kind
trap - EXIT; rm -rf "$TMP"
echo "kind v${KIND_VERSION} installed."

# --- minikube ---
echo "Installing minikube..."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 \
  -o "$TMP/minikube"
install "$TMP/minikube" ~/.local/bin/minikube
trap - EXIT; rm -rf "$TMP"
echo "minikube $(minikube version --short) installed."

echo ""
echo "Container tools installed: ctop, dive, lazydocker, k9s, kubectl, helm, k3d, kind, minikube"
