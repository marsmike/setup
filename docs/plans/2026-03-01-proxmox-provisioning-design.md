# Homelab as Code — Design Document
*2026-03-01*

## Goal

Consolidate all homelab knowledge into the setup repo so that:
1. Nothing lives only on a node (no more "what did I do 3 weeks ago?")
2. Any machine (Mac, Linux, MobaXterm/Windows) can run the scripts
3. Claude can provision VMs autonomously: "spin up a dev VM with RagFlow" → done

---

## Repo Structure

```
setup/
├── mac/                        # Mac-specific bootstrap
│   ├── 00_sshkey.sh            # Generate + display local SSH key
│   ├── 01_basics.sh            # Homebrew, core CLI tools
│   ├── mx-keys-fix.sh          # MX Keys keyboard fix
│   ├── quickemu_install.sh
│   └── quickgui_install.sh
│
├── linux/                      # Linux machine bootstrap (servers, VMs, WSL)
│   ├── 00_bootstrap.sh         # NEW: root-access → create user, upload key, harden SSH
│   ├── 00_adduser.sh
│   ├── 00_sudoers.sh
│   ├── 00_sshd.sh
│   ├── 01_basics.sh
│   ├── 02_dotfiles.sh
│   └── 03_shell.sh
│
├── tools/                      # Tool installs — run on any Linux/Mac
│   ├── 10_neovim.sh
│   ├── 10_lazygit.sh
│   ├── 10_kubectl.sh
│   ├── 10_helm.sh
│   ├── 10_k3d.sh
│   ├── 10_claude.sh
│   ├── 10_ai_tools.sh
│   ├── 10_llm_tools.sh
│   ├── 11_docker_tools.sh
│   ├── 20_atuin.sh
│   ├── 20_uv.sh
│   ├── 20_conda.sh
│   ├── 20_kind.sh
│   ├── 20_minikube.sh
│   ├── 20_coder.sh
│   ├── 20_teleport.sh
│   ├── 20_restic.sh
│   └── 20_fonts.sh
│
├── proxmox/
│   ├── nodes.yaml              # Cluster inventory (nodes, IPs, storage)
│   ├── secrets.env.example     # Template — copy to secrets.env and fill in
│   ├── provision.sh            # Main entrypoint: provision.sh vms/ragflow.yaml
│   ├── scripts/
│   │   ├── create_vm.sh        # Non-interactive VM creation (flags, no prompts)
│   │   └── template.sh         # Build/rebuild the Ubuntu Noble template (VM 8200)
│   ├── cloudinit/
│   │   └── base.yaml.tpl       # Cloud-init template with all dev tools baked in
│   ├── profiles/               # Reusable hardware + toolchain presets
│   │   ├── dev-base.yaml       # 4 cores / 8 GB / 32 GB — standard dev VM
│   │   └── ai-workbench.yaml   # 8 cores / 24 GB / 96 GB — heavy AI workloads
│   ├── apps/                   # Application stacks layered on profiles
│   │   ├── ragflow.yaml        # RagFlow: docker-compose + post-install steps
│   │   ├── local-ai.yaml       # LocalAI setup
│   │   └── n8n.yaml            # n8n workflow automation
│   └── vms/                    # Concrete VM instances (the live inventory)
│       ├── ragflow.yaml        # profile: dev-base, app: ragflow, node: pve-node-01
│       ├── local-ai.yaml       # profile: ai-workbench, app: local-ai, node: pve-node-01
│       └── pihole.yaml         # LXC container, node: pve-node-01
│
└── docs/
    └── plans/
        └── 2026-03-01-proxmox-provisioning-design.md   # this file
```

---

## Secrets Management

**Never commit real secrets.** The approach is a local `secrets.env` file that is
gitignored, with a committed `secrets.env.example` showing exactly what's needed.

```
# proxmox/secrets.env.example  ← committed to git
PROXMOX_USER=root
PROXMOX_PASS=
PROXMOX_SSH_PASS=            # same as PROXMOX_PASS if using password auth

SSH_PUBLIC_KEY=              # your public key, pasted inline
USER_PASSWORD_HASH=          # sha512 hash of VM user password (mkpasswd -m sha-512)
CHEZMOI_USER=marsmike        # GitHub username for chezmoi dotfiles
```

```
# proxmox/secrets.env         ← gitignored, filled in locally on each machine
PROXMOX_USER=root
PROXMOX_PASS=...
SSH_PUBLIC_KEY="ssh-rsa AAAA..."
USER_PASSWORD_HASH='$5$...'
CHEZMOI_USER=marsmike
```

`provision.sh` sources `secrets.env` at startup. This works identically on Mac,
Linux, and MobaXterm (bash). No extra tooling required.

To set up on a new machine: `cp proxmox/secrets.env.example proxmox/secrets.env`
then fill in the values.

---

## VM Model: Three Layers

### Layer 1 — Profile (hardware + base toolchain)

```yaml
# profiles/dev-base.yaml
hardware:
  memory: 8192
  cores: 4
  disk: 32G
  storage: nvme

cloudinit:
  packages:
    - qemu-guest-agent
    - docker
    - git
    - gh
    - neovim
    - zsh
    - tmux
    - htop
    - jq
    - python3
    - build-essential
  post_install:
    - install_ohmyzsh
    - install_chezmoi
    - install_docker
    - install_ctop
```

### Layer 2 — App stack

```yaml
# apps/ragflow.yaml
description: "RAG-based document Q&A platform"
port: 80
compose_url: "https://raw.githubusercontent.com/infiniflow/ragflow/main/docker/docker-compose.yml"
post_start:
  - "docker compose up -d"
notes: "Needs 8GB+ RAM. Access via http://<VM_IP>"
```

### Layer 3 — VM instance

```yaml
# vms/ragflow.yaml
profile: dev-base
app: ragflow

vm:
  id: 100
  name: ragflow
  node: pve-node-01

network:
  ip: 192.168.1.100
  gateway: 192.168.1.1
  netmask: 24
  dns: 192.168.1.1
  searchdomain: home
```

---

## Cluster Inventory (`nodes.yaml`)

```yaml
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

ip_range:
  start: 192.168.1.100
  end:   192.168.1.199
  gateway: 192.168.1.1
  netmask: 24
  dns: 192.168.1.1

vmid_range:
  start: 100
  end:   899
```

---

## Provisioning Flow

```
./proxmox/provision.sh vms/ragflow.yaml
         │
         ├── 1. source secrets.env
         ├── 2. parse VM YAML (yq) → merge profile + app
         ├── 3. render cloudinit/base.yaml.tpl → /tmp/<name>-cloudinit.yaml
         ├── 4. SSH to target node
         │       ├── upload rendered cloud-init to /var/lib/vz/snippets/
         │       └── invoke create_vm.sh --name ragflow --ip 192.168.1.100 ...
         └── 5. tail progress / report done
```

**Dependencies (all available on Mac, Linux, MobaXterm bash):**
- `bash` — runs the scripts
- `ssh` / `sshpass` — remote execution (sshpass for password auth bootstrap)
- `yq` — YAML parsing in shell (single binary, cross-platform)
- `envsubst` — template rendering (part of gettext, standard on Linux; `brew install gettext` on Mac)

---

## Initial Bootstrap Flow (fresh Linux host)

For a brand-new host with only root+password access:

```
./linux/00_bootstrap.sh <HOST_IP>
         │
         ├── SSHes as root (password from secrets.env or prompt)
         ├── Creates user 'mike' with sudo NOPASSWD
         ├── Uploads SSH_PUBLIC_KEY from secrets.env
         ├── Hardens sshd: key-only auth, no root login, no passwords
         └── Reports: "Host secured. Connect with: ssh mike@<HOST_IP>"
```

This script works identically whether the host is a bare metal server, a Proxmox
VM, a VPS, or a Raspberry Pi. It's the first step after `provision.sh` finishes
(which handles the cloud-init equivalent for Proxmox VMs).

---

## How Claude Operates This

When you say: *"Spin up a dev VM with RagFlow on node 2"*

1. Read `proxmox/nodes.yaml` → resolve `pve-node-02` → `192.168.1.102`
2. Read `proxmox/profiles/dev-base.yaml` + `proxmox/apps/ragflow.yaml`
3. Scan `proxmox/vms/` + `nodes.yaml` ip_range → find next free VMID and IP
4. Write `proxmox/vms/ragflow-v2.yaml` with the composed config
5. Run `./proxmox/provision.sh proxmox/vms/ragflow-v2.yaml` (SSH to node)
6. Commit the new `vms/ragflow-v2.yaml` so the inventory stays current
7. Report: VM name, IP, how to connect

The repo is always the source of truth. Every VM that exists has a file in `vms/`.

---

## Not In Scope (for now)

- VM deletion / lifecycle management beyond creation
- Snapshots and backups
- Multi-node template replication (template stays on node-01)
- Networking beyond flat VLAN (VXLAN config is separate)
