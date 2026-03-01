# Homelab as Code — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reorganize the setup repo into mac/linux/tools/proxmox, extract all Proxmox VM knowledge from node-01 into the repo, and build a fully automated provisioning system operable by Claude.

**Architecture:** Three-layer VM model (profile + app + instance). `provision.sh` reads a VM YAML, merges it with a profile and app definition, renders a cloud-init template, SSHes to the target Proxmox node, and creates the VM non-interactively. Secrets stay in a gitignored `.env` file consistent with the existing repo pattern.

**Tech Stack:** bash, ssh/sshpass, yq (mikefarah YAML processor, already installed by `01_basics_linux.sh`), envsubst (gettext), Proxmox `qm` CLI (runs on the node)

---

## Task 1: Repo Reorganization

**Files:**
- Create dirs: `mac/`, `linux/`, `tools/`
- git mv all existing root-level scripts

**Step 1: Create directories and move Mac scripts**

```bash
cd /Users/mike/work/setup
mkdir -p mac linux tools

git mv 00_local_sshkey.sh    mac/00_sshkey.sh
git mv 01_basics_macos.sh    mac/01_basics.sh
git mv mx-keys-fix.sh        mac/mx-keys-fix.sh
git mv quickemu_install.sh   mac/quickemu_install.sh
git mv quickgui_install.sh   mac/quickgui_install.sh
```

**Step 2: Move Linux bootstrap scripts**

```bash
git mv 00_server_adduser.sh  linux/00_adduser.sh
git mv 00_server_sudoers.sh  linux/00_sudoers.sh
git mv 00_server_sshd.sh     linux/00_sshd.sh
git mv 01_basics_linux.sh    linux/01_basics.sh
git mv 02_dotfiles.sh        linux/02_dotfiles.sh
git mv 03_shell.sh           linux/03_shell.sh
git mv test_pipeline.sh      linux/test_pipeline.sh
git mv 60-vxlan.cfg          linux/60-vxlan.cfg
git mv docker-grub.txt       linux/docker-grub.txt
```

**Step 3: Move tool scripts**

```bash
git mv 10_lazygit.sh       tools/10_lazygit.sh
git mv 10_helm.sh          tools/10_helm.sh
git mv 10_k3d.sh           tools/10_k3d.sh
git mv 10_kubectl.sh       tools/10_kubectl.sh
git mv 10_ai_tools.sh      tools/10_ai_tools.sh
git mv 10_claude.sh        tools/10_claude.sh
git mv 10_neovim.sh        tools/10_neovim.sh
git mv 10_llm_tools.sh     tools/10_llm_tools.sh
git mv 11_docker_tools.sh  tools/11_docker_tools.sh
git mv 20_atuin.sh         tools/20_atuin.sh
git mv 20_uv.sh            tools/20_uv.sh
git mv 20_conda.sh         tools/20_conda.sh
git mv 20_kind.sh          tools/20_kind.sh
git mv 20_minikube.sh      tools/20_minikube.sh
git mv 20_coder.sh         tools/20_coder.sh
git mv 20_teleport.sh      tools/20_teleport.sh
git mv 20_restic.sh        tools/20_restic.sh
git mv 20_fonts.sh         tools/20_fonts.sh
git mv yabs.sh             tools/yabs.sh
```

**Step 4: Validate — no stray files at root**

```bash
ls *.sh 2>/dev/null && echo "ERROR: scripts still at root" || echo "OK"
```
Expected: `OK`

**Step 5: Commit**

```bash
git commit -m "refactor: reorganize scripts into mac/ linux/ tools/ folders"
```

---

## Task 2: Proxmox Folder Structure + Secrets Template

**Files:**
- Create: `proxmox/.env.example`
- Modify: `.gitignore`
- Create dirs: `proxmox/scripts/`, `proxmox/cloudinit/`, `proxmox/profiles/`, `proxmox/apps/`, `proxmox/vms/`

**Step 1: Create directory structure**

```bash
mkdir -p proxmox/scripts proxmox/cloudinit proxmox/profiles proxmox/apps proxmox/vms
```

**Step 2: Create `proxmox/.env.example`**

```bash
cat > proxmox/.env.example << 'EOF'
# Copy this file to proxmox/.env and fill in your values.
# proxmox/.env is gitignored — never commit real secrets.
#
# On a new machine: cp proxmox/.env.example proxmox/.env
# Generate a password hash: mkpasswd -m sha-512 yourpassword

# Proxmox access (root SSH)
PROXMOX_USER=root
PROXMOX_PASS=

# Your identity (baked into every VM)
SSH_PUBLIC_KEY=
USER_PASSWORD_HASH=
CHEZMOI_USER=marsmike

# GitHub token for dotfiles (used by linux/02_dotfiles.sh)
GH_TOKEN=
DOTFILES_REPO=
SETUP_USER=mike
EOF
```

**Step 3: Update `.gitignore` to also cover the proxmox `.env`**

The existing `.gitignore` already contains `.env` which git treats as matching
any `.env` in any subdirectory. Verify:

```bash
echo "proxmox/test.env" > proxmox/test.env
git check-ignore -v proxmox/test.env || echo "NOT ignored — fix gitignore"
rm proxmox/test.env
```
Expected: shows `.env` rule matches.

If not matched, append to `.gitignore`:
```
proxmox/.env
```

**Step 4: Commit**

```bash
git add proxmox/.env.example .gitignore
git commit -m "feat(proxmox): add folder structure and secrets template"
```

---

## Task 3: Cluster Inventory (`nodes.yaml`)

**Files:**
- Create: `proxmox/nodes.yaml`

**Step 1: Create the inventory file**

```bash
cat > proxmox/nodes.yaml << 'EOF'
# Proxmox cluster inventory
# Used by provision.sh to resolve node names to IPs and storage pools.

nodes:
  - name: pve-node-01
    ip: 192.168.1.101
    storage: nvme
    notes: "Template host — ubuntu-24-04-cloud (VM 8200) lives here"

  - name: pve-node-02
    ip: 192.168.1.102
    storage: local-lvm

  - name: pve-node-03
    ip: 192.168.1.103
    storage: local-lvm

# IP pool for new VMs (Claude scans vms/ to find the next free address)
ip_pool:
  start: 192.168.1.100
  end:   192.168.1.199
  gateway: 192.168.1.1
  netmask: 24
  dns: 192.168.1.1
  searchdomain: home

# VMID pool for new VMs
vmid_pool:
  start: 100
  end:   899
EOF
```

**Step 2: Validate YAML parses correctly**

```bash
yq eval '.' proxmox/nodes.yaml
```
Expected: clean YAML output, no errors.

**Step 3: Commit**

```bash
git add proxmox/nodes.yaml
git commit -m "feat(proxmox): add cluster inventory nodes.yaml"
```

---

## Task 4: VM Profiles

**Files:**
- Create: `proxmox/profiles/dev-base.yaml`
- Create: `proxmox/profiles/ai-workbench.yaml`

**Step 1: Create `dev-base.yaml`**

```bash
cat > proxmox/profiles/dev-base.yaml << 'EOF'
# Standard development VM — full toolchain, moderate hardware
# Covers: Docker, git, neovim, zsh, tmux, Python, Node, chezmoi dotfiles

hardware:
  memory: 8192    # MB
  cores: 4
  disk: 32G
  storage: nvme   # overridden per-node by nodes.yaml if needed

cloudinit:
  base_template: cloudinit/base.yaml.tpl
EOF
```

**Step 2: Create `ai-workbench.yaml`**

```bash
cat > proxmox/profiles/ai-workbench.yaml << 'EOF'
# Heavy AI workload VM — large RAM for local models and RAG pipelines

hardware:
  memory: 24576   # 24 GB
  cores: 8
  disk: 96G
  storage: nvme

cloudinit:
  base_template: cloudinit/base.yaml.tpl
EOF
```

**Step 3: Validate both files**

```bash
yq eval '.' proxmox/profiles/dev-base.yaml
yq eval '.' proxmox/profiles/ai-workbench.yaml
```

**Step 4: Commit**

```bash
git add proxmox/profiles/
git commit -m "feat(proxmox): add dev-base and ai-workbench VM profiles"
```

---

## Task 5: App Stacks

**Files:**
- Create: `proxmox/apps/ragflow.yaml`
- Create: `proxmox/apps/local-ai.yaml`
- Create: `proxmox/apps/n8n.yaml`

**Step 1: Create `ragflow.yaml`**

```bash
cat > proxmox/apps/ragflow.yaml << 'EOF'
# RAGFlow — RAG-based document Q&A platform
# Repo: https://github.com/infiniflow/ragflow
# Needs 8GB+ RAM. Use with profile: ai-workbench (or dev-base at minimum).
# Access: http://<VM_IP> after provisioning

description: "RAG-based document Q&A and knowledge management"
port: 80

# These commands run on the VM after cloud-init completes
# provision.sh SSHes to the VM IP and runs them in order
post_provision:
  - "mkdir -p ~/ragflow && cd ~/ragflow"
  - "curl -fsSL https://raw.githubusercontent.com/infiniflow/ragflow/main/docker/docker-compose.yml -o docker-compose.yml"
  - "docker compose up -d"

notes: |
  First login: visit http://<VM_IP> — create admin account on first visit.
  Logs: ssh mike@<VM_IP> 'cd ~/ragflow && docker compose logs -f'
EOF
```

**Step 2: Create `local-ai.yaml`**

```bash
cat > proxmox/apps/local-ai.yaml << 'EOF'
# LocalAI — self-hosted OpenAI-compatible API
# Repo: https://github.com/mudler/LocalAI
# Use with profile: ai-workbench (GPU passthrough optional)

description: "Self-hosted OpenAI-compatible inference API"
port: 8080

post_provision:
  - "mkdir -p ~/localai/models"
  - >
    docker run -d --name localai
    -p 8080:8080
    -v ~/localai/models:/models
    -e MODELS_PATH=/models
    localai/localai:latest

notes: |
  API endpoint: http://<VM_IP>:8080/v1
  Drop GGUF model files into ~/localai/models/ and restart container.
EOF
```

**Step 3: Create `n8n.yaml`**

```bash
cat > proxmox/apps/n8n.yaml << 'EOF'
# n8n — workflow automation platform
# Use with profile: dev-base

description: "Self-hosted workflow automation (like Zapier)"
port: 5678

post_provision:
  - "mkdir -p ~/n8n"
  - >
    docker run -d --name n8n
    --restart unless-stopped
    -p 5678:5678
    -v ~/n8n:/home/node/.n8n
    -e N8N_BASIC_AUTH_ACTIVE=true
    -e N8N_BASIC_AUTH_USER=admin
    -e N8N_BASIC_AUTH_PASSWORD=changeme
    n8nio/n8n:latest

notes: |
  Access: http://<VM_IP>:5678 — user: admin / pass: changeme (change on first login)
EOF
```

**Step 4: Validate all app files**

```bash
for f in proxmox/apps/*.yaml; do
  echo "--- $f ---"
  yq eval '.' "$f"
done
```

**Step 5: Commit**

```bash
git add proxmox/apps/
git commit -m "feat(proxmox): add ragflow, local-ai, n8n app stack definitions"
```

---

## Task 6: Document Existing VMs

**Files:**
- Create: `proxmox/vms/ragflow.yaml`
- Create: `proxmox/vms/local-ai.yaml`
- Create: `proxmox/vms/pihole.yaml`

These document what's currently running on pve-node-01. They serve as the live
inventory and allow re-provisioning from scratch if needed.

**Step 1: Create `vms/ragflow.yaml`**

```bash
cat > proxmox/vms/ragflow.yaml << 'EOF'
# Existing VM — pve-node-01, VMID 100
# Provisioned manually. This file documents the config for re-creation.
profile: dev-base
app: ragflow

vm:
  id: 100
  name: ragflow
  node: pve-node-01

hardware:
  memory: 10000
  cores: 8
  disk: 32G

network:
  ip: 192.168.1.100
  gateway: 192.168.1.1
  netmask: 24
  dns: 192.168.1.1
  searchdomain: home
EOF
```

**Step 2: Create `vms/local-ai.yaml`**

```bash
cat > proxmox/vms/local-ai.yaml << 'EOF'
# Existing VM — pve-node-01, VMID 101
profile: ai-workbench
app: local-ai

vm:
  id: 101
  name: local-ai
  node: pve-node-01

hardware:
  memory: 25000
  cores: 8
  disk: 96G

network:
  ip: 192.168.1.101
  gateway: 192.168.1.1
  netmask: 24
  dns: 192.168.1.1
  searchdomain: home
EOF
```

**Step 3: Create `vms/pihole.yaml`**

```bash
cat > proxmox/vms/pihole.yaml << 'EOF'
# Existing LXC container — pve-node-01, CTID 5001
# NOTE: LXC containers use 'pct' not 'qm' — provision.sh does not manage these yet.
type: lxc

lxc:
  id: 5001
  name: pihole
  node: pve-node-01

hardware:
  memory: 1024
  cores: 2
  disk: 4G

network:
  ip: 192.168.1.2
  gateway: 192.168.1.1
  netmask: 24

notes: "DNS + ad blocking. Tags: dhcp, dns"
EOF
```

**Step 4: Validate all VM files**

```bash
for f in proxmox/vms/*.yaml; do
  echo "--- $f ---"
  yq eval '.' "$f"
done
```

**Step 5: Commit**

```bash
git add proxmox/vms/
git commit -m "feat(proxmox): document existing VMs as inventory (ragflow, local-ai, pihole)"
```

---

## Task 7: Cloud-Init Base Template

**Files:**
- Create: `proxmox/cloudinit/base.yaml.tpl`

This is the cloud-init config extracted and generalized from the existing
`create.sh` on pve-node-01. Variables use `${VAR}` syntax for `envsubst`.

**Critical:** `envsubst` is called with an explicit variable list so it only
substitutes our placeholders — leaving password hashes (`$5$...`) and other
dollar signs in the YAML untouched.

**Step 1: Create the template**

```bash
cat > proxmox/cloudinit/base.yaml.tpl << 'TPLEOF'
#cloud-config
hostname: ${VM_NAME}
manage_etc_hosts: true
fqdn: ${VM_NAME}.${VM_SEARCHDOMAIN}

users:
  - name: mike
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: false
    passwd: ${USER_PASSWORD_HASH}
    ssh_authorized_keys:
      - ${SSH_PUBLIC_KEY}

package_upgrade: true
packages:
  - qemu-guest-agent
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - software-properties-common
  - git
  - gh
  - vim
  - neovim
  - python3
  - python3-pip
  - python3-venv
  - tmux
  - zsh
  - htop
  - tree
  - jq
  - wget
  - unzip
  - build-essential

write_files:
  - path: /etc/ssh/sshd_config.d/50-cloud-init.conf
    content: |
      PasswordAuthentication yes
      PubkeyAuthentication yes
      PermitRootLogin no
  - path: /etc/sysctl.d/99-enable-ipv4-forwarding.conf
    content: |
      net.ipv4.conf.all.forwarding=1

runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - systemctl enable ssh
  - systemctl restart ssh
  - curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  - sh /tmp/get-docker.sh
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker mike
  - rm /tmp/get-docker.sh
  - wget -q https://github.com/bcicen/ctop/releases/download/v0.7.7/ctop-0.7.7-linux-amd64 -O /usr/local/bin/ctop
  - chmod +x /usr/local/bin/ctop
  - chown -R mike:mike /home/mike
  - |
    su - mike << 'MIKESCRIPT'
    set -e
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    fi
    if [ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]; then
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k
    fi
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
      git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    fi
    if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
      git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    fi
    if [ ! -f "$HOME/.local/bin/chezmoi" ]; then
      sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply ${CHEZMOI_USER}
      mkdir -p $HOME/.local/bin
      [ -f "$HOME/bin/chezmoi" ] && mv $HOME/bin/chezmoi $HOME/.local/bin/chezmoi
      rm -rf $HOME/bin
    fi
    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm
    fi
    MIKESCRIPT
  - chsh -s /usr/bin/zsh mike

power_state:
  mode: reboot
  message: "Cloud-init complete. Rebooting..."
  timeout: 60
  condition: True

final_message: "VM ready. Docker + dev tools installed. System rebooting."
TPLEOF
```

**Step 2: Test that envsubst renders it correctly without touching `$HOME` etc.**

```bash
export VM_NAME=test-vm VM_SEARCHDOMAIN=home
export SSH_PUBLIC_KEY="ssh-rsa AAAA..."
export USER_PASSWORD_HASH='$5$test$hash'
export CHEZMOI_USER=marsmike

envsubst '${VM_NAME} ${VM_SEARCHDOMAIN} ${SSH_PUBLIC_KEY} ${USER_PASSWORD_HASH} ${CHEZMOI_USER}' \
  < proxmox/cloudinit/base.yaml.tpl > /tmp/test-cloudinit.yaml

# Verify password hash is untouched (envsubst must NOT have eaten it)
grep 'passwd:' /tmp/test-cloudinit.yaml
# Expected line: "    passwd: $5$test$hash"

# Verify VM_NAME substituted
grep 'hostname:' /tmp/test-cloudinit.yaml
# Expected: "hostname: test-vm"

rm /tmp/test-cloudinit.yaml
```

**Step 3: Commit**

```bash
git add proxmox/cloudinit/base.yaml.tpl
git commit -m "feat(proxmox): add cloud-init base template (extracted from node create.sh)"
```

---

## Task 8: Non-Interactive `create_vm.sh`

**Files:**
- Create: `proxmox/scripts/create_vm.sh`

This runs **on the Proxmox node** (uploaded and executed by `provision.sh` via SSH).
It is the non-interactive replacement for the existing `/root/create.sh` on pve-node-01.

**Step 1: Create the script**

```bash
cat > proxmox/scripts/create_vm.sh << 'EOF'
#!/bin/bash
# Non-interactive VM creation — runs on the Proxmox node.
# Uploaded and invoked by provision.sh via SSH.
#
# Usage: create_vm.sh --vmid 100 --name ragflow --ip 192.168.1.100 \
#          --netmask 24 --gateway 192.168.1.1 --dns 192.168.1.1 \
#          --searchdomain home --memory 8192 --cores 4 --disk 32G \
#          --storage nvme --cloudinit /var/lib/vz/snippets/ragflow-cloudinit.yaml

set -euo pipefail

IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_FILE="/root/noble-server-cloudimg-amd64.img"

# Parse flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vmid)        VMID="$2";         shift 2 ;;
    --name)        VM_NAME="$2";      shift 2 ;;
    --storage)     STORAGE="$2";      shift 2 ;;
    --memory)      MEMORY="$2";       shift 2 ;;
    --cores)       CORES="$2";        shift 2 ;;
    --disk)        DISK="$2";         shift 2 ;;
    --ip)          VM_IP="$2";        shift 2 ;;
    --netmask)     VM_NETMASK="$2";   shift 2 ;;
    --gateway)     VM_GATEWAY="$2";   shift 2 ;;
    --dns)         VM_DNS="$2";       shift 2 ;;
    --searchdomain) VM_SEARCHDOMAIN="$2"; shift 2 ;;
    --cloudinit)   CLOUDINIT_FILE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Validate required flags
for var in VMID VM_NAME STORAGE MEMORY CORES DISK VM_IP VM_NETMASK VM_GATEWAY VM_DNS VM_SEARCHDOMAIN CLOUDINIT_FILE; do
  [ -z "${!var:-}" ] && { echo "ERROR: --${var,,} is required" >&2; exit 1; }
done

echo "========================================"
echo "  Creating VM: $VM_NAME (ID: $VMID)"
echo "========================================"

# Download cloud image if not cached
if [ ! -f "$IMAGE_FILE" ]; then
  echo "Downloading Ubuntu Noble cloud image..."
  wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"
fi

# Resize image to requested disk size
echo "Resizing image to $DISK..."
qemu-img resize "$IMAGE_FILE" "$DISK"

# Destroy existing VM with same ID (idempotent)
echo "Removing existing VM $VMID if present..."
qm destroy "$VMID" 2>/dev/null || true

# Create VM
echo "Creating VM $VMID..."
qm create "$VMID" \
  --name "$VM_NAME" \
  --ostype l26 \
  --memory "$MEMORY" \
  --balloon 0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --cpu host \
  --sockets 1 \
  --cores "$CORES" \
  --vga serial0 \
  --serial0 socket \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,firewall=1

# Import disk
echo "Importing disk..."
qm set "$VMID" --scsi0 "${STORAGE}:0,import-from=${IMAGE_FILE},discard=on,ssd=1"

# Cloud-init drive
echo "Adding cloud-init drive..."
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"

# Boot order
qm set "$VMID" --boot order=scsi0

# Apply cloud-init snippet
SNIPPET_NAME="$(basename "$CLOUDINIT_FILE")"
echo "Applying cloud-init: $SNIPPET_NAME"
qm set "$VMID" --cicustom "user=local:snippets/${SNIPPET_NAME}"

# Static network
echo "Configuring network: $VM_IP/$VM_NETMASK gw $VM_GATEWAY"
qm set "$VMID" --ipconfig0 "ip=${VM_IP}/${VM_NETMASK},gw=${VM_GATEWAY}"
qm set "$VMID" --nameserver "$VM_DNS"
qm set "$VMID" --searchdomain "$VM_SEARCHDOMAIN"

# Tags
qm set "$VMID" --tags "ubuntu-noble,docker,dev-env"

# Regenerate cloud-init ISO
echo "Generating cloud-init drive..."
qm cloudinit update "$VMID"

# Start VM
echo "Starting VM..."
qm start "$VMID"

echo ""
echo "========================================"
echo "  VM $VM_NAME ($VMID) started!"
echo "========================================"
echo "  IP:     $VM_IP"
echo "  SSH:    ssh mike@$VM_IP"
echo "  Wait ~3-5 min for cloud-init to complete."
echo "  Monitor: qm status $VMID"
EOF

chmod +x proxmox/scripts/create_vm.sh
```

**Step 2: Syntax check**

```bash
bash -n proxmox/scripts/create_vm.sh && echo "Syntax OK"
```
Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add proxmox/scripts/create_vm.sh
git commit -m "feat(proxmox): add non-interactive create_vm.sh (replaces interactive create.sh)"
```

---

## Task 9: Template Builder (`template.sh`)

**Files:**
- Create: `proxmox/scripts/template.sh`

Builds/rebuilds the base Ubuntu Noble template (VM 8200) on a given node.
Parameterized version of the existing `/root/ubuntu-noble-cloudinit.sh` on pve-node-01.
Run this when the template needs to be refreshed or set up on a new node.

**Step 1: Create the script**

```bash
cat > proxmox/scripts/template.sh << 'EOF'
#!/bin/bash
# Build the Ubuntu Noble cloud-init template (VM 8200) on this Proxmox node.
# Runs ON the node (uploaded by provision.sh or run manually via SSH).
#
# Usage: template.sh [--template-id 8200] [--storage nvme]

set -euo pipefail

TEMPLATE_ID="${1:-8200}"
STORAGE="${2:-nvme}"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_FILE="noble-server-cloudimg-amd64.img"

echo "Building Ubuntu Noble template (VM $TEMPLATE_ID) on storage: $STORAGE"

if [ ! -f "$IMAGE_FILE" ]; then
  echo "Downloading Ubuntu Noble cloud image..."
  wget -q --show-progress "$IMAGE_URL"
fi

echo "Resizing image to 32G..."
qemu-img resize "$IMAGE_FILE" 32G

echo "Removing existing template $TEMPLATE_ID if present..."
qm destroy "$TEMPLATE_ID" 2>/dev/null || true

echo "Creating template VM..."
qm create "$TEMPLATE_ID" \
  --name "ubuntu-24-04-cloud" \
  --ostype l26 \
  --memory 8192 \
  --balloon 0 \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --cpu host \
  --sockets 1 \
  --cores 4 \
  --vga serial0 \
  --serial0 socket \
  --scsihw virtio-scsi-single \
  --net0 virtio,bridge=vmbr0,firewall=1

echo "Importing disk..."
qm set "$TEMPLATE_ID" --scsi0 "${STORAGE}:0,import-from=/root/${IMAGE_FILE},discard=on,ssd=1"
qm set "$TEMPLATE_ID" --ide2 "${STORAGE}:cloudinit"
qm set "$TEMPLATE_ID" --boot order=scsi0
qm set "$TEMPLATE_ID" --tags "ubuntu-noble,cloudinit,template"
qm cloudinit update "$TEMPLATE_ID"

echo "Converting to template..."
qm template "$TEMPLATE_ID"

echo ""
echo "Template $TEMPLATE_ID ready on $STORAGE."
echo "Clone with: qm clone $TEMPLATE_ID <NEWID> --name <NAME> --full"
EOF

chmod +x proxmox/scripts/template.sh
```

**Step 2: Syntax check**

```bash
bash -n proxmox/scripts/template.sh && echo "Syntax OK"
```

**Step 3: Commit**

```bash
git add proxmox/scripts/template.sh
git commit -m "feat(proxmox): add parameterized template.sh (replaces ubuntu-noble-cloudinit.sh)"
```

---

## Task 10: Main Orchestrator (`provision.sh`)

**Files:**
- Create: `proxmox/provision.sh`

**Step 1: Create the script**

```bash
cat > proxmox/provision.sh << 'EOF'
#!/bin/bash
# Provision a Proxmox VM from a YAML definition.
# Reads proxmox/.env for secrets.
#
# Usage:
#   ./proxmox/provision.sh proxmox/vms/ragflow.yaml
#   ./proxmox/provision.sh proxmox/vms/ragflow.yaml --dry-run
#
# Requirements on the running machine:
#   - bash, ssh, scp
#   - yq  (mikefarah): https://github.com/mikefarah/yq
#   - envsubst (gettext): brew install gettext / apt install gettext
#   - sshpass (if using password auth): brew install sshpass / apt install sshpass

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_YAML="${1:-}"
DRY_RUN="${2:-}"

# --- Validate input ---
if [ -z "$VM_YAML" ]; then
  echo "Usage: $0 <path/to/vms/vm.yaml> [--dry-run]" >&2
  exit 1
fi
if [ ! -f "$VM_YAML" ]; then
  echo "ERROR: VM file not found: $VM_YAML" >&2
  exit 1
fi

# --- Load secrets ---
ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found." >&2
  echo "Run: cp ${SCRIPT_DIR}/.env.example ${SCRIPT_DIR}/.env" >&2
  echo "Then fill in your secrets." >&2
  exit 1
fi
set -o allexport
source "$ENV_FILE"
set +o allexport

# Validate required secrets
for var in SSH_PUBLIC_KEY USER_PASSWORD_HASH CHEZMOI_USER; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set in $ENV_FILE" >&2
    exit 1
  fi
done

# --- Parse VM YAML ---
VM_NAME=$(yq '.vm.name'  "$VM_YAML")
VM_ID=$(yq   '.vm.id'    "$VM_YAML")
NODE_NAME=$(yq '.vm.node' "$VM_YAML")
PROFILE=$(yq   '.profile' "$VM_YAML")

# Override hardware from VM YAML if set, otherwise fall through to profile
MEMORY=$(yq -e '.hardware.memory // ""' "$VM_YAML" 2>/dev/null || echo "")
CORES=$(yq  -e '.hardware.cores  // ""' "$VM_YAML" 2>/dev/null || echo "")
DISK=$(yq   -e '.hardware.disk   // ""' "$VM_YAML" 2>/dev/null || echo "")

# Load profile defaults for any unset values
PROFILE_FILE="${SCRIPT_DIR}/profiles/${PROFILE}.yaml"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "ERROR: Profile not found: $PROFILE_FILE" >&2
  exit 1
fi
[ -z "$MEMORY" ] && MEMORY=$(yq '.hardware.memory' "$PROFILE_FILE")
[ -z "$CORES"  ] && CORES=$(yq  '.hardware.cores'  "$PROFILE_FILE")
[ -z "$DISK"   ] && DISK=$(yq   '.hardware.disk'   "$PROFILE_FILE")

# Network — use nodes.yaml defaults if not specified in VM YAML
NODES_FILE="${SCRIPT_DIR}/nodes.yaml"
DEFAULT_GATEWAY=$(yq '.ip_pool.gateway'      "$NODES_FILE")
DEFAULT_NETMASK=$(yq '.ip_pool.netmask'      "$NODES_FILE")
DEFAULT_DNS=$(yq     '.ip_pool.dns'          "$NODES_FILE")
DEFAULT_DOMAIN=$(yq  '.ip_pool.searchdomain' "$NODES_FILE")

VM_IP=$(yq          '.network.ip'           "$VM_YAML")
VM_GATEWAY=$(yq -e  '.network.gateway // ""' "$VM_YAML" 2>/dev/null || echo "$DEFAULT_GATEWAY")
VM_NETMASK=$(yq -e  '.network.netmask // ""' "$VM_YAML" 2>/dev/null || echo "$DEFAULT_NETMASK")
VM_DNS=$(yq -e      '.network.dns     // ""' "$VM_YAML" 2>/dev/null || echo "$DEFAULT_DNS")
VM_SEARCHDOMAIN=$(yq -e '.network.searchdomain // ""' "$VM_YAML" 2>/dev/null || echo "$DEFAULT_DOMAIN")

# Resolve node IP and storage from nodes.yaml
NODE_IP=$(yq ".nodes[] | select(.name == \"${NODE_NAME}\") | .ip" "$NODES_FILE")
NODE_STORAGE=$(yq ".nodes[] | select(.name == \"${NODE_NAME}\") | .storage" "$NODES_FILE")
# Allow VM YAML to override storage
VM_STORAGE=$(yq -e '.hardware.storage // ""' "$VM_YAML" 2>/dev/null || echo "")
[ -n "$VM_STORAGE" ] && NODE_STORAGE="$VM_STORAGE"

if [ -z "$NODE_IP" ]; then
  echo "ERROR: Node '$NODE_NAME' not found in $NODES_FILE" >&2
  exit 1
fi

# --- Render cloud-init template ---
TPL_FILE="${SCRIPT_DIR}/cloudinit/base.yaml.tpl"
RENDERED_FILE="/tmp/${VM_NAME}-cloudinit.yaml"

export VM_NAME VM_SEARCHDOMAIN SSH_PUBLIC_KEY USER_PASSWORD_HASH CHEZMOI_USER
envsubst '${VM_NAME} ${VM_SEARCHDOMAIN} ${SSH_PUBLIC_KEY} ${USER_PASSWORD_HASH} ${CHEZMOI_USER}' \
  < "$TPL_FILE" > "$RENDERED_FILE"

# --- Summary ---
echo "========================================"
echo "  VM Provisioning Plan"
echo "========================================"
echo "  VM YAML:    $VM_YAML"
echo "  Name:       $VM_NAME (ID: $VM_ID)"
echo "  Node:       $NODE_NAME ($NODE_IP)"
echo "  Storage:    $NODE_STORAGE"
echo "  Profile:    $PROFILE"
echo "  Hardware:   ${MEMORY}MB RAM | ${CORES} cores | $DISK disk"
echo "  Network:    $VM_IP/$VM_NETMASK gw $VM_GATEWAY"
echo "========================================"

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo ""
  echo "DRY RUN — no changes made. Rendered cloud-init:"
  echo "---"
  cat "$RENDERED_FILE"
  exit 0
fi

# --- SSH helper ---
# Try key-based auth first. Fall back to sshpass if password is set.
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
if ssh $SSH_OPTS -o BatchMode=yes "${PROXMOX_USER:-root}@${NODE_IP}" exit 2>/dev/null; then
  SSH_PREFIX=""
elif [ -n "${PROXMOX_PASS:-}" ] && command -v sshpass &>/dev/null; then
  SSH_PREFIX="sshpass -p ${PROXMOX_PASS}"
else
  echo "ERROR: Cannot authenticate to $NODE_IP." >&2
  echo "  Option 1: Set up SSH key auth (recommended)" >&2
  echo "  Option 2: Set PROXMOX_PASS in .env and install sshpass" >&2
  echo "            Mac: brew install sshpass" >&2
  echo "            Linux: apt install sshpass" >&2
  exit 1
fi

RUN_NODE()  { $SSH_PREFIX ssh  $SSH_OPTS "${PROXMOX_USER:-root}@${NODE_IP}" "$@"; }
COPY_NODE() { $SSH_PREFIX scp  $SSH_OPTS "$1" "${PROXMOX_USER:-root}@${NODE_IP}:$2"; }

# --- Upload cloud-init snippet ---
echo "Uploading cloud-init config to $NODE_NAME..."
RUN_NODE "mkdir -p /var/lib/vz/snippets"
COPY_NODE "$RENDERED_FILE" "/var/lib/vz/snippets/${VM_NAME}-cloudinit.yaml"

# --- Upload create_vm.sh ---
echo "Uploading create_vm.sh..."
COPY_NODE "${SCRIPT_DIR}/scripts/create_vm.sh" "/tmp/create_vm_${VM_NAME}.sh"
RUN_NODE "chmod +x /tmp/create_vm_${VM_NAME}.sh"

# --- Run creation ---
echo "Creating VM on $NODE_NAME..."
RUN_NODE "/tmp/create_vm_${VM_NAME}.sh \
  --vmid ${VM_ID} \
  --name ${VM_NAME} \
  --storage ${NODE_STORAGE} \
  --memory ${MEMORY} \
  --cores ${CORES} \
  --disk ${DISK} \
  --ip ${VM_IP} \
  --netmask ${VM_NETMASK} \
  --gateway ${VM_GATEWAY} \
  --dns ${VM_DNS} \
  --searchdomain ${VM_SEARCHDOMAIN} \
  --cloudinit /var/lib/vz/snippets/${VM_NAME}-cloudinit.yaml"

# Cleanup temp file on node
RUN_NODE "rm -f /tmp/create_vm_${VM_NAME}.sh" 2>/dev/null || true

echo ""
echo "========================================"
echo "  Done! VM $VM_NAME is starting."
echo "========================================"
echo "  SSH (after ~3-5 min):  ssh mike@${VM_IP}"
echo "  Monitor:               ssh ${PROXMOX_USER:-root}@${NODE_IP} 'qm status ${VM_ID}'"
echo "  Cloud-init log:        ssh mike@${VM_IP} 'sudo tail -f /var/log/cloud-init-output.log'"
EOF

chmod +x proxmox/provision.sh
```

**Step 2: Syntax check**

```bash
bash -n proxmox/provision.sh && echo "Syntax OK"
```

**Step 3: Dry-run test (no SSH needed)**

```bash
# Create a minimal .env for testing
cat > proxmox/.env << 'EOF'
PROXMOX_USER=root
PROXMOX_PASS=test
SSH_PUBLIC_KEY="ssh-rsa AAAA..."
USER_PASSWORD_HASH='$5$test$hash'
CHEZMOI_USER=marsmike
EOF

./proxmox/provision.sh proxmox/vms/ragflow.yaml --dry-run
```
Expected: prints the plan summary and rendered cloud-init YAML, exits 0.

**Step 4: Commit**

```bash
git add proxmox/provision.sh
git commit -m "feat(proxmox): add provision.sh orchestrator with dry-run support"
```

---

## Task 11: Initial Host Bootstrap (`linux/00_bootstrap.sh`)

**Files:**
- Create: `linux/00_bootstrap.sh`

Turns a fresh Linux host (root+password SSH only) into a secured, ready machine.
Works on bare metal, Proxmox VMs, VPSes, Raspberry Pis. Cross-platform: runs
from Mac, MobaXterm, Linux — needs only bash + ssh/sshpass.

**Step 1: Create the script**

```bash
cat > linux/00_bootstrap.sh << 'EOF'
#!/bin/bash
# Bootstrap a fresh Linux host: create user, upload SSH key, harden SSH.
# Runs from your LOCAL machine (Mac, Linux, MobaXterm) — not on the host.
#
# The host must have root SSH access (password) to start.
# After this script, only key-based SSH as SETUP_USER is allowed.
#
# Usage:
#   bash linux/00_bootstrap.sh <HOST_IP>
#   bash linux/00_bootstrap.sh <HOST_IP> --root-pass 'mypassword'
#
# Secrets sourced from .env (or proxmox/.env):
#   SETUP_USER, SSH_PUBLIC_KEY, ROOT_PASS (optional override)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HOST_IP="${1:-}"
if [ -z "$HOST_IP" ]; then
  echo "Usage: $0 <HOST_IP> [--root-pass 'password']" >&2
  exit 1
fi

# Parse optional --root-pass flag
ROOT_PASS_OVERRIDE=""
shift
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root-pass) ROOT_PASS_OVERRIDE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Load secrets from proxmox/.env first, fall back to .env in repo root
for ENV_FILE in "${REPO_ROOT}/proxmox/.env" "${REPO_ROOT}/.env" "${SCRIPT_DIR}/.env"; do
  if [ -f "$ENV_FILE" ]; then
    set -o allexport
    source "$ENV_FILE"
    set +o allexport
    break
  fi
done

SETUP_USER="${SETUP_USER:-mike}"
ROOT_PASS="${ROOT_PASS_OVERRIDE:-${ROOT_PASS:-}}"

if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
  echo "ERROR: SSH_PUBLIC_KEY is not set. Add it to proxmox/.env" >&2
  exit 1
fi

# Build SSH command prefix
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
if [ -n "$ROOT_PASS" ] && command -v sshpass &>/dev/null; then
  SSH_AS_ROOT="sshpass -p ${ROOT_PASS} ssh $SSH_OPTS root@${HOST_IP}"
elif [ -n "$ROOT_PASS" ]; then
  echo "WARNING: PROXMOX_PASS is set but sshpass is not installed." >&2
  echo "  Mac: brew install sshpass | Linux: apt install sshpass" >&2
  echo "Falling back to interactive password prompt." >&2
  SSH_AS_ROOT="ssh $SSH_OPTS root@${HOST_IP}"
else
  SSH_AS_ROOT="ssh $SSH_OPTS root@${HOST_IP}"
fi

echo "========================================"
echo "  Bootstrapping: $HOST_IP"
echo "  User to create: $SETUP_USER"
echo "========================================"

# --- Step 1: Create user ---
echo "[1/4] Creating user '$SETUP_USER'..."
$SSH_AS_ROOT "
  id $SETUP_USER 2>/dev/null && echo 'User already exists, skipping.' || \
  adduser --disabled-password --gecos '' $SETUP_USER
  usermod -aG sudo $SETUP_USER
"

# --- Step 2: Passwordless sudo ---
echo "[2/4] Configuring passwordless sudo..."
$SSH_AS_ROOT "
  echo '$SETUP_USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/${SETUP_USER}-nopasswd
  chmod 440 /etc/sudoers.d/${SETUP_USER}-nopasswd
  visudo -c -f /etc/sudoers.d/${SETUP_USER}-nopasswd
"

# --- Step 3: Upload SSH key ---
echo "[3/4] Uploading SSH key..."
$SSH_AS_ROOT "
  mkdir -p /home/$SETUP_USER/.ssh
  echo '${SSH_PUBLIC_KEY}' >> /home/$SETUP_USER/.ssh/authorized_keys
  sort -u /home/$SETUP_USER/.ssh/authorized_keys -o /home/$SETUP_USER/.ssh/authorized_keys
  chmod 700 /home/$SETUP_USER/.ssh
  chmod 600 /home/$SETUP_USER/.ssh/authorized_keys
  chown -R $SETUP_USER:$SETUP_USER /home/$SETUP_USER/.ssh
"

# --- Step 4: Harden SSH ---
echo "[4/4] Hardening sshd (key-only, no root login, no passwords)..."
$SSH_AS_ROOT "
  sed -i 's/.*PubkeyAuthentication.*/PubkeyAuthentication yes/'   /etc/ssh/sshd_config
  sed -i 's/.*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
  sed -i 's/.*PermitRootLogin.*/PermitRootLogin no/'              /etc/ssh/sshd_config
  systemctl restart sshd
"

echo ""
echo "========================================"
echo "  Bootstrap complete!"
echo "========================================"
echo "  Connect: ssh ${SETUP_USER}@${HOST_IP}"
echo "  Root login and password auth are now disabled."
EOF

chmod +x linux/00_bootstrap.sh
```

**Step 2: Syntax check**

```bash
bash -n linux/00_bootstrap.sh && echo "Syntax OK"
```

**Step 3: Commit**

```bash
git add linux/00_bootstrap.sh
git commit -m "feat(linux): add 00_bootstrap.sh — fresh host setup from root+password to key-only"
```

---

## Task 12: Integration Test

End-to-end verification: provision a real test VM on pve-node-01.

**Step 1: Set up secrets**

```bash
# Fill in real values
cp proxmox/.env.example proxmox/.env
# Edit proxmox/.env with your SSH key, password hash, and Proxmox credentials
```

**Step 2: Create a test VM definition**

```bash
cat > proxmox/vms/test-vm.yaml << 'EOF'
profile: dev-base
vm:
  id: 200
  name: test-vm
  node: pve-node-01
hardware:
  memory: 4096
  cores: 2
  disk: 16G
network:
  ip: 192.168.1.150
  gateway: 192.168.1.1
  netmask: 24
  dns: 192.168.1.1
  searchdomain: home
EOF
```

**Step 3: Dry run first**

```bash
./proxmox/provision.sh proxmox/vms/test-vm.yaml --dry-run
```
Expected: prints plan + rendered cloud-init, no errors.

**Step 4: Provision for real**

```bash
./proxmox/provision.sh proxmox/vms/test-vm.yaml
```
Expected: VM starts on node-01. Waits 3-5 min for cloud-init.

**Step 5: Verify**

```bash
# Check VM is running
ssh root@192.168.1.101 'qm status 200'
# Expected: status: running

# Wait for cloud-init, then SSH in
ssh mike@192.168.1.150 'docker --version && zsh --version && chezmoi --version'
```

**Step 6: Cleanup test VM**

```bash
ssh root@192.168.1.101 'qm stop 200; qm destroy 200'
rm proxmox/vms/test-vm.yaml
git add -A && git commit -m "test(proxmox): verified end-to-end VM provisioning"
```

---

## Quick Reference for Claude

When asked to provision a VM:

1. `cat proxmox/nodes.yaml` — find a node with capacity
2. `ls proxmox/vms/` + `yq '.network.ip' proxmox/vms/*.yaml` — find next free IP
3. `yq '.vm.id' proxmox/vms/*.yaml | sort -n | tail -1` — find next free VMID
4. Write `proxmox/vms/<name>.yaml` with profile, app, node, hardware, network
5. `./proxmox/provision.sh proxmox/vms/<name>.yaml --dry-run` — verify
6. `./proxmox/provision.sh proxmox/vms/<name>.yaml` — provision
7. `git add proxmox/vms/<name>.yaml && git commit -m "feat(vms): add <name>"` — record it
