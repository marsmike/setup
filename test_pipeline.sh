#!/bin/bash
# Tests the Linux setup pipeline in a clean, isolated environment.
#
# Backends (auto-detected; override with --backend):
#   docker   — Ubuntu 24.04 container (no KVM needed; works on any VPS)
#   quickemu — Full Ubuntu Server 24.04 VM (requires /dev/kvm)
#
# Usage:
#   bash test_pipeline.sh                    # auto-detect backend
#   bash test_pipeline.sh --backend docker   # force Docker
#   bash test_pipeline.sh --backend quickemu # force quickemu
#   bash test_pipeline.sh --keep             # leave container/VM running after tests
#   bash test_pipeline.sh --clean            # destroy previous environment first
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${HOME}/.pipeline-test"
CONTAINER_NAME="setup-pipeline-test"
VM_BASE="${WORK_DIR}/quickemu"
VM_NAME="ubuntu-server-24.04"
VM_CONF="${VM_BASE}/${VM_NAME}.conf"
SSH_KEY="${VM_BASE}/test_id_ed25519"
SEED_ISO="${VM_BASE}/seed.iso"
VM_SSH_USER="ubuntu"
BACKEND=""
KEEP=false
CLEAN=false
FAILURES=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
pass()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; FAILURES=$((FAILURES + 1)); }
info()   { echo -e "${YELLOW}▶${NC} $1"; }
header() { echo -e "\n${BOLD}── $1 ──${NC}"; }

for arg in "$@"; do
  case $arg in
    --backend) ;;
    docker|quickemu) BACKEND=$arg ;;
    --backend=docker) BACKEND=docker ;;
    --backend=quickemu) BACKEND=quickemu ;;
    --keep) KEEP=true ;;
    --clean) CLEAN=true ;;
  esac
done

# ── Auto-detect backend ───────────────────────────────────────────────────────
if [ -z "$BACKEND" ]; then
  if [ -e /dev/kvm ] && command -v quickemu &>/dev/null; then
    BACKEND=quickemu
  elif command -v docker &>/dev/null; then
    BACKEND=docker
  else
    echo "No backend available: need Docker or quickemu+KVM."
    exit 1
  fi
fi
info "Backend: ${BACKEND}"

# ═══════════════════════════════════════════════════════════════════════════════
# DOCKER BACKEND
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$BACKEND" = "docker" ]; then

  # Prereqs
  header "Prerequisites"
  command -v docker &>/dev/null && pass "docker" || { fail "docker not found"; exit 1; }

  # Clean
  if $CLEAN; then
    info "Removing previous container..."
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
  fi

  # Start container
  header "Starting container"
  if docker inspect "${CONTAINER_NAME}" &>/dev/null; then
    info "Reusing existing container"
  else
    info "Pulling ubuntu:24.04..."
    docker pull ubuntu:24.04 -q
    docker run -d \
      --name "${CONTAINER_NAME}" \
      --hostname setup-test \
      --privileged \
      ubuntu:24.04 sleep infinity
    info "Bootstrapping user environment..."
    docker exec "${CONTAINER_NAME}" bash -c "
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y --no-install-recommends sudo curl ca-certificates git tzdata locales 2>/dev/null
      useradd -m -s /bin/bash ubuntu
      echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/ubuntu
      chmod 440 /etc/sudoers.d/ubuntu
      touch /home/ubuntu/.zsh_history
      chown ubuntu:ubuntu /home/ubuntu/.zsh_history
    "
  fi
  pass "Container ready"

  # Upload scripts
  header "Uploading setup scripts"
  for f in "${SCRIPT_DIR}"/*.sh; do
    docker cp "$f" "${CONTAINER_NAME}:/home/ubuntu/$(basename "$f")" 2>/dev/null
  done
  docker exec "${CONTAINER_NAME}" chown -R ubuntu:ubuntu /home/ubuntu/
  pass "Scripts uploaded"

  if [ -f "${SCRIPT_DIR}/.env" ]; then
    docker cp "${SCRIPT_DIR}/.env" "${CONTAINER_NAME}:/home/ubuntu/.env"
    pass ".env uploaded"
    HAS_ENV=true
  else
    info "No .env — 02_dotfiles.sh will be skipped"
    HAS_ENV=false
  fi

  # Run a script inside the container as the ubuntu user
  run_phase() {
    local script="$1" label="$2"
    header "Running ${script}"
    mkdir -p "${WORK_DIR}/logs"
    if docker exec \
        -u ubuntu \
        -e HOME=/home/ubuntu \
        -e USER=ubuntu \
        -e DEBIAN_FRONTEND=noninteractive \
        "${CONTAINER_NAME}" \
        bash "/home/ubuntu/${script}" 2>&1 | tee "${WORK_DIR}/logs/${script}.log"; then
      pass "${label}"
    else
      fail "${label} — see ${WORK_DIR}/logs/${script}.log"
    fi
  }

  # Check a command inside the container
  check() {
    local label="$1" cmd="$2"
    if docker exec -u ubuntu -e HOME=/home/ubuntu "${CONTAINER_NAME}" \
        bash -c "source /home/ubuntu/.nvm/nvm.sh 2>/dev/null; $cmd" >/dev/null 2>&1; then
      pass "$label"
    else
      fail "$label"
    fi
  }

  # Cleanup
  cleanup() {
    if ! $KEEP; then
      info "Removing container..."
      docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    else
      info "Container left running — inspect with: docker exec -it ${CONTAINER_NAME} bash"
    fi
  }

# ═══════════════════════════════════════════════════════════════════════════════
# QUICKEMU BACKEND
# ═══════════════════════════════════════════════════════════════════════════════
else

  # Prereqs
  header "Prerequisites"
  for cmd in quickemu quickget genisoimage ssh scp openssl; do
    command -v "$cmd" &>/dev/null && pass "$cmd" \
      || { fail "$cmd not found — run: bash quickemu_install.sh"; FAILURES=$((FAILURES+1)); }
  done
  [ $FAILURES -gt 0 ] && exit 1

  # Clean
  if $CLEAN && [ -d "${VM_BASE}" ]; then
    info "Removing previous VM..."
    pkill -f "quickemu.*${VM_NAME}" 2>/dev/null || true
    sleep 2; rm -rf "${VM_BASE}"
  fi
  mkdir -p "${VM_BASE}"

  # SSH key
  if [ ! -f "${SSH_KEY}" ]; then
    info "Generating test SSH key..."
    ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "quickemu-test" >/dev/null
  fi
  SSH_PUBKEY="$(cat "${SSH_KEY}.pub")"

  # Cloud-init seed
  if [ ! -f "${SEED_ISO}" ]; then
    info "Creating autoinstall seed ISO..."
    HASHED_PW="$(openssl passwd -6 'ubuntu-test')"
    cat > "${VM_BASE}/user-data" <<USERDATA
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: setup-test
    username: ${VM_SSH_USER}
    password: '${HASHED_PW}'
  ssh:
    install-server: true
    allow-pw: false
    authorized-keys:
      - ${SSH_PUBKEY}
  storage:
    layout:
      name: direct
  late-commands:
    - echo '${VM_SSH_USER} ALL=(ALL) NOPASSWD:ALL' > /target/etc/sudoers.d/${VM_SSH_USER}-nopasswd
    - chmod 440 /target/etc/sudoers.d/${VM_SSH_USER}-nopasswd
USERDATA
    printf 'instance-id: setup-test-001\nlocal-hostname: setup-test\n' > "${VM_BASE}/meta-data"
    genisoimage -output "${SEED_ISO}" -volid cidata -joliet -rock \
      "${VM_BASE}/user-data" "${VM_BASE}/meta-data" 2>/dev/null
  fi

  # Download ISO
  if [ ! -f "${VM_CONF}" ]; then
    info "Downloading Ubuntu Server 24.04 (~1.5 GB)..."
    (cd "${VM_BASE}" && quickget ubuntu-server 24.04)
    echo "" >> "${VM_CONF}"
    echo "# Autoinstall seed — appended by test_pipeline.sh" >> "${VM_CONF}"
    echo "extra_args=\"-drive file=${SEED_ISO},if=virtio,format=raw\"" >> "${VM_CONF}"
  fi

  # Boot VM
  header "Starting VM"
  LOG_FILE="${VM_BASE}/quickemu.log"
  SSH_PORT_FILE="${VM_BASE}/ssh_port"
  INSTALLED_FLAG="${VM_BASE}/.installed"
  MAX_WAIT=600
  [ -f "${INSTALLED_FLAG}" ] && MAX_WAIT=120

  if ! pgrep -f "quickemu.*${VM_NAME}" >/dev/null 2>&1; then
    [ -f "${INSTALLED_FLAG}" ] \
      && info "Booting existing VM..." \
      || info "First boot — Ubuntu autoinstall (~8 min)..."
    rm -f "${LOG_FILE}" "${SSH_PORT_FILE}"
    quickemu --vm "${VM_CONF}" --display none > "${LOG_FILE}" 2>&1 &

    ELAPSED=0
    while [ $ELAPSED -lt 60 ]; do
      grep -q "ssh -p" "${LOG_FILE}" 2>/dev/null \
        && { grep -oP 'ssh -p \K[0-9]+' "${LOG_FILE}" | head -1 > "${SSH_PORT_FILE}"; break; }
      sleep 2; ELAPSED=$((ELAPSED+2))
    done
    [ -f "${SSH_PORT_FILE}" ] || { fail "Could not read SSH port — check ${LOG_FILE}"; exit 1; }
  fi

  SSH_PORT="$(cat "${SSH_PORT_FILE}")"
  SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -p ${SSH_PORT} -i ${SSH_KEY}"

  header "Waiting for SSH (port ${SSH_PORT})"
  ELAPSED=0
  while [ $ELAPSED -lt $MAX_WAIT ]; do
    ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "echo ok" >/dev/null 2>&1 \
      && { pass "SSH up"; touch "${INSTALLED_FLAG}"; break; }
    printf '.'; sleep 10; ELAPSED=$((ELAPSED+10))
  done
  echo ""
  ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "echo ok" >/dev/null 2>&1 \
    || { fail "VM unreachable — check ${LOG_FILE}"; exit 1; }

  # Upload scripts
  header "Uploading setup scripts"
  scp $SSH_OPTS "${SCRIPT_DIR}"/*.sh "${VM_SSH_USER}@localhost:/home/${VM_SSH_USER}/" >/dev/null
  pass "Scripts uploaded"

  if [ -f "${SCRIPT_DIR}/.env" ]; then
    scp $SSH_OPTS "${SCRIPT_DIR}/.env" "${VM_SSH_USER}@localhost:/home/${VM_SSH_USER}/.env" >/dev/null
    pass ".env uploaded"; HAS_ENV=true
  else
    info "No .env — 02_dotfiles.sh will be skipped"; HAS_ENV=false
  fi

  run_phase() {
    local script="$1" label="$2"
    header "Running ${script}"
    mkdir -p "${WORK_DIR}/logs"
    if ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "cd ~ && bash ${script}" \
        2>&1 | tee "${WORK_DIR}/logs/${script}.log"; then
      pass "${label}"
    else
      fail "${label} — see ${WORK_DIR}/logs/${script}.log"
    fi
  }

  check() {
    local label="$1" cmd="$2"
    ssh $SSH_OPTS "${VM_SSH_USER}@localhost" \
        "source ~/.nvm/nvm.sh 2>/dev/null; $cmd" >/dev/null 2>&1 \
      && pass "$label" || fail "$label"
  }

  cleanup() {
    if ! $KEEP; then
      info "Shutting down VM..."
      ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "sudo poweroff" >/dev/null 2>&1 || true
      sleep 3; pkill -f "quickemu.*${VM_NAME}" 2>/dev/null || true
    else
      info "VM left running — ssh -p ${SSH_PORT} -i ${SSH_KEY} ${VM_SSH_USER}@localhost"
    fi
  }
fi

# ── Run pipeline ──────────────────────────────────────────────────────────────
run_phase "01_basics_linux.sh" "Phase 1: basics"
${HAS_ENV} && run_phase "02_dotfiles.sh" "Phase 1: dotfiles"
run_phase "03_shell.sh" "Phase 1: shell (oh-my-zsh + powerlevel10k)"

# ── Verify ────────────────────────────────────────────────────────────────────
header "Verifying installation"
check "zsh"                   "zsh --version"
check "git"                   "git --version"
check "node"                  "node --version"
check "python3"               "python3 --version"
check "bat"                   "bat --version"
check "eza"                   "eza --version"
check "ripgrep"               "rg --version"
check "fzf"                   "fzf --version"
check "jq"                    "jq --version"
check "tmux"                  "tmux -V"
check "btop"                  "btop --version"
check "delta"                 "delta --version"
check "yq"                    "yq --version"
check "glow"                  "glow --version"
check "watchexec"             "watchexec --version"
check "csvlens"               "csvlens --version"
check "oh-my-zsh"             "[ -d ~/.oh-my-zsh ]"
check "powerlevel10k"         "[ -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]"
check "zsh-autosuggestions"   "[ -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]"
check "zsh-syntax-highlighting" "[ -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]"
check "atuin guard"           "grep -q 'command -v atuin' ~/.zshrc || ! grep -q 'atuin' ~/.zshrc"

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
if [ $FAILURES -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed. Pipeline is good.${NC}"
else
  echo -e "${RED}${BOLD}${FAILURES} check(s) failed.${NC} Logs: ${WORK_DIR}/logs/"
fi
echo "════════════════════════════════════════"

cleanup
[ $FAILURES -eq 0 ]
