#!/bin/bash
# bootstrap/lib.sh
# Shared helpers for the bootstrap scripts. Sourced, never run directly.

BOOTSTRAP_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load config from ~/.env (canonical) or the repo-root .env. Values set inline
# on the command line win, so `SSH_USER=root bash ...` always takes effect.
load_setup_env() {
  local inline_ssh_user="${SSH_USER-}" inline_ignoreip="${FAIL2BAN_IGNOREIP-}"
  local inline_host="${SETUP_HOST-}" inline_key="${SETUP_SSH_KEY-}"
  local env_file
  for env_file in "${HOME}/.env" "${BOOTSTRAP_REPO_ROOT}/.env"; do
    if [ -f "${env_file}" ]; then
      set -o allexport
      # shellcheck source=/dev/null
      source "${env_file}"
      set +o allexport
      break
    fi
  done
  [ -n "${inline_ssh_user}" ] && SSH_USER="${inline_ssh_user}"
  [ -n "${inline_ignoreip}" ] && FAIL2BAN_IGNOREIP="${inline_ignoreip}"
  [ -n "${inline_host}" ] && SETUP_HOST="${inline_host}"
  [ -n "${inline_key}" ] && SETUP_SSH_KEY="${inline_key}"

  # Every server gets its own key, so one compromised host exposes nothing else.
  local key_host="${SETUP_HOST:-}"
  key_host="${key_host#*@}"
  if [ -n "${SETUP_SSH_KEY:-}" ]; then
    KEY_PATH="${SETUP_SSH_KEY}"
  elif [ -n "${key_host}" ]; then
    KEY_PATH="${HOME}/.ssh/id_ed25519_${key_host}"
  else
    echo "ERROR: set SETUP_HOST or SETUP_SSH_KEY in ~/.env or inline." >&2
    exit 1
  fi
  return 0
}

# Make plain `ssh <host>` offer only this host's key, and never forward the agent.
ensure_ssh_config_entry() {
  local host="$1" config="${HOME}/.ssh/config"
  if [ -f "${config}" ] && grep -qiE "^Host[[:space:]]+${host//./\\.}([[:space:]]|\$)" "${config}"; then
    echo "${config} already has an entry for ${host}, leaving it unchanged."
    return 0
  fi
  {
    [ ! -s "${config}" ] || echo ""
    echo "Host ${host}"
    echo "  IdentityFile ${KEY_PATH}"
    echo "  IdentitiesOnly yes"
    echo "  ForwardAgent no"
  } >> "${config}"
  chmod 600 "${config}"
  echo "Added ${host} to ${config}."
}

# Validate SETUP_USER/SETUP_HOST and derive HOST_ONLY and SSH_USER.
require_setup_target() {
  SETUP_USER="${SETUP_USER:-}"
  SETUP_HOST="${SETUP_HOST:-}"
  if [ -z "${SETUP_USER}" ] || [ -z "${SETUP_HOST}" ]; then
    echo "ERROR: SETUP_USER and SETUP_HOST must be set in ~/.env or inline." >&2
    exit 1
  fi
  if ! [[ "${SETUP_USER}" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
    echo "ERROR: SETUP_USER '${SETUP_USER}' is not a valid Linux user name." >&2
    exit 1
  fi
  HOST_ONLY="${SETUP_HOST#*@}"
  SSH_USER="${SSH_USER:-${SETUP_USER}}"
}

# ssh offering only this host's key when it exists, so other keys are never
# shown to the server and can't count toward a fail2ban ban.
setup_ssh() {
  if [ -f "${KEY_PATH}" ]; then
    ssh -i "${KEY_PATH}" -o IdentitiesOnly=yes -o ConnectTimeout=15 "$@"
  else
    ssh -o ConnectTimeout=15 "$@"
  fi
}

# Run a script from stdin on the server as root, connecting as SSH_USER.
# Arguments are NAME=value pairs exported to that script.
run_remote_root() {
  local command="env" assignment
  for assignment in "$@"; do
    command+=" $(printf '%q' "${assignment}")"
  done
  [ "${SSH_USER}" = "root" ] || command="sudo -n ${command}"
  setup_ssh "${SSH_USER}@${HOST_ONLY}" "${command} bash -s"
}

# Confirm SETUP_USER can open a new key-based session and use sudo.
require_user_access() {
  if ! setup_ssh -o BatchMode=yes "${SETUP_USER}@${HOST_ONLY}" 'sudo -n true'; then
    echo "ERROR: ${SETUP_USER}@${HOST_ONLY} has no working key login with passwordless sudo." >&2
    echo "  Run bootstrap/server/04_adduser.sh and 05_sudoers.sh with SSH_USER=root first." >&2
    exit 1
  fi
}
