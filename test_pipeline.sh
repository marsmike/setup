#!/bin/bash
# Tests the Linux setup pipeline in a fresh quickemu Ubuntu 24.04 VM.
#
# Usage:
#   bash test_pipeline.sh             # run all phases
#   bash test_pipeline.sh --keep-vm   # leave VM running after tests (for debugging)
#   bash test_pipeline.sh --clean     # destroy previous test VM and start fresh
#
# Prerequisites: quickemu, quickget, genisoimage (all from quickemu_install.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_BASE="${HOME}/.quickemu-test"
VM_NAME="ubuntu-24.04"
VM_CONF="${VM_BASE}/${VM_NAME}.conf"
SSH_KEY="${VM_BASE}/test_id_ed25519"
SEED_ISO="${VM_BASE}/seed.iso"
LOG_FILE="${VM_BASE}/quickemu.log"
SSH_PORT_FILE="${VM_BASE}/ssh_port"
INSTALLED_FLAG="${VM_BASE}/.installed"
VM_SSH_USER="ubuntu"
MAX_INSTALL_WAIT=600  # 10 min for Ubuntu autoinstall
MAX_BOOT_WAIT=120     # 2 min for subsequent boots
KEEP_VM=false
CLEAN=false
FAILURES=0

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'
pass()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail()   { echo -e "  ${RED}✗${NC} $1"; FAILURES=$((FAILURES + 1)); }
info()   { echo -e "${YELLOW}▶${NC} $1"; }
header() { echo -e "\n${BOLD}── $1 ──${NC}"; }

for arg in "$@"; do
  case $arg in --keep-vm) KEEP_VM=true ;; --clean) CLEAN=true ;; esac
done

# ── Prereqs ──────────────────────────────────────────────────────────────────
header "Prerequisites"
MISSING=()
for cmd in quickemu quickget genisoimage ssh scp openssl; do
  if command -v "$cmd" &>/dev/null; then pass "$cmd"
  else fail "$cmd not found"; MISSING+=("$cmd"); fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "Install missing tools: bash quickemu_install.sh"
  exit 1
fi

# ── Clean ─────────────────────────────────────────────────────────────────────
if $CLEAN && [ -d "${VM_BASE}" ]; then
  info "Removing previous test VM..."
  pkill -f "quickemu.*${VM_NAME}" 2>/dev/null || true
  sleep 2
  rm -rf "${VM_BASE}"
fi
mkdir -p "${VM_BASE}"

# ── SSH key ───────────────────────────────────────────────────────────────────
if [ ! -f "${SSH_KEY}" ]; then
  info "Generating test SSH key..."
  ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "quickemu-test" >/dev/null
fi
SSH_PUBKEY="$(cat "${SSH_KEY}.pub")"

# ── Cloud-init seed ISO ───────────────────────────────────────────────────────
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

# ── Download Ubuntu 24.04 ─────────────────────────────────────────────────────
if [ ! -f "${VM_CONF}" ]; then
  info "Downloading Ubuntu 24.04 (this may take a while — ISO is ~2 GB)..."
  (cd "${VM_BASE}" && quickget ubuntu 24.04)
  # Attach seed ISO so Ubuntu autoinstall finds the cloud-init nocloud datasource
  echo "" >> "${VM_CONF}"
  echo "# Autoinstall seed — appended by test_pipeline.sh" >> "${VM_CONF}"
  echo "extra_args=\"-drive file=${SEED_ISO},if=virtio,format=raw\"" >> "${VM_CONF}"
fi

# ── Boot VM ───────────────────────────────────────────────────────────────────
header "Starting VM"
if ! pgrep -f "quickemu.*${VM_NAME}" >/dev/null 2>&1; then
  if [ -f "${INSTALLED_FLAG}" ]; then
    info "Using existing installed VM..."
    MAX_WAIT=$MAX_BOOT_WAIT
  else
    info "First boot — Ubuntu autoinstall in progress (up to 10 min)..."
    MAX_WAIT=$MAX_INSTALL_WAIT
  fi
  rm -f "${LOG_FILE}" "${SSH_PORT_FILE}"
  quickemu --vm "${VM_CONF}" --display none > "${LOG_FILE}" 2>&1 &

  info "Waiting for SSH port..."
  ELAPSED=0
  while [ $ELAPSED -lt 60 ]; do
    if grep -q "ssh -p" "${LOG_FILE}" 2>/dev/null; then
      SSH_PORT=$(grep -oP 'ssh -p \K[0-9]+' "${LOG_FILE}" | head -1)
      echo "${SSH_PORT}" > "${SSH_PORT_FILE}"
      break
    fi
    sleep 2; ELAPSED=$((ELAPSED + 2))
  done
  [ -f "${SSH_PORT_FILE}" ] || { fail "Could not read SSH port from quickemu output — check ${LOG_FILE}"; exit 1; }
fi

SSH_PORT="$(cat "${SSH_PORT_FILE}")"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes -p ${SSH_PORT} -i ${SSH_KEY}"
MAX_WAIT="${MAX_WAIT:-$MAX_BOOT_WAIT}"

# ── Wait for SSH ──────────────────────────────────────────────────────────────
header "Waiting for SSH (port ${SSH_PORT})"
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
  if ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "echo ok" >/dev/null 2>&1; then
    pass "SSH is up"
    touch "${INSTALLED_FLAG}"
    break
  fi
  printf '.'
  sleep 10; ELAPSED=$((ELAPSED + 10))
done
echo ""
if ! ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "echo ok" >/dev/null 2>&1; then
  fail "VM never became SSH-accessible — check ${LOG_FILE}"
  exit 1
fi

# ── Upload scripts ────────────────────────────────────────────────────────────
header "Uploading setup scripts"
scp $SSH_OPTS "${SCRIPT_DIR}"/*.sh "${VM_SSH_USER}@localhost:/home/${VM_SSH_USER}/" >/dev/null
pass "Scripts uploaded"

HAS_ENV=false
if [ -f "${SCRIPT_DIR}/.env" ]; then
  scp $SSH_OPTS "${SCRIPT_DIR}/.env" "${VM_SSH_USER}@localhost:/home/${VM_SSH_USER}/" >/dev/null
  pass ".env uploaded"
  HAS_ENV=true
else
  info "No .env found — 02_dotfiles.sh will be skipped"
fi

# ── Run pipeline ──────────────────────────────────────────────────────────────
run_phase() {
  local script="$1" label="$2"
  header "Running ${script}"
  if ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "cd ~ && bash ${script}" \
       2>&1 | tee "${VM_BASE}/${script}.log" | grep -E '(error|Error|FAIL|installed|done|Done)' || true; then
    local rc=${PIPESTATUS[0]}
    [ $rc -eq 0 ] && pass "${label}" || { fail "${label} — see ${VM_BASE}/${script}.log"; }
  fi
}

run_phase "01_basics_linux.sh" "Phase 1: basics"
$HAS_ENV && run_phase "02_dotfiles.sh" "Phase 1: dotfiles"
run_phase "03_shell.sh" "Phase 1: shell (oh-my-zsh + powerlevel10k)"

# ── Verify binaries ───────────────────────────────────────────────────────────
header "Verifying installation"
declare -A CHECKS=(
  ["zsh"]="zsh --version"
  ["git"]="git --version"
  ["node"]="~/.nvm/nvm.sh && node --version"
  ["python3"]="python3 --version"
  ["bat"]="bat --version"
  ["eza"]="eza --version"
  ["ripgrep"]="rg --version"
  ["fzf"]="fzf --version"
  ["jq"]="jq --version"
  ["tmux"]="tmux -V"
  ["btop"]="btop --version"
  ["delta"]="delta --version"
  ["yq"]="yq --version"
  ["glow"]="glow --version"
  ["watchexec"]="watchexec --version"
  ["csvlens"]="csvlens --version"
  ["oh-my-zsh"]="[ -d ~/.oh-my-zsh ]"
  ["powerlevel10k"]="[ -d ~/.oh-my-zsh/custom/themes/powerlevel10k ]"
  ["zsh-autosuggestions"]="[ -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]"
  ["zsh-syntax-highlighting"]="[ -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]"
  ["atuin guard"]="grep -q 'command -v atuin' ~/.zshrc || ! grep -q 'atuin' ~/.zshrc"
)

for label in "${!CHECKS[@]}"; do
  cmd="${CHECKS[$label]}"
  if ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "source ~/.nvm/nvm.sh 2>/dev/null; $cmd" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
  fi
done

# ── Result ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
if [ $FAILURES -eq 0 ]; then
  echo -e "${GREEN}${BOLD}All checks passed. Pipeline is good.${NC}"
else
  echo -e "${RED}${BOLD}${FAILURES} check(s) failed.${NC}"
  echo "Logs are in ${VM_BASE}/"
fi
echo "════════════════════════════════════════"

# ── Shutdown ──────────────────────────────────────────────────────────────────
if ! $KEEP_VM; then
  info "Shutting down VM..."
  ssh $SSH_OPTS "${VM_SSH_USER}@localhost" "sudo poweroff" >/dev/null 2>&1 || true
  sleep 3
  pkill -f "quickemu.*${VM_NAME}" 2>/dev/null || true
else
  info "VM left running — SSH: ssh -p ${SSH_PORT} -i ${SSH_KEY} ${VM_SSH_USER}@localhost"
fi

[ $FAILURES -eq 0 ]
