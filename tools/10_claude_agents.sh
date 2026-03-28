#!/bin/bash
# Spawn persistent Claude Code sessions inside tmux with auto-setup.
# Idempotent — safe to re-run; skips windows that are already active.
#
# After launching Claude instances, automatically sends post-start
# commands (e.g., /remote-control, /whatsapp-start). Includes retry
# logic for soft failures and WhatsApp alerts for auth errors.
#
# Usage:
#   ./10_claude_agents.sh              # create session + windows only
#   ./10_claude_agents.sh --start      # create, launch, and post-start
#   ./10_claude_agents.sh --restart    # stop everything, then --start
#   ./10_claude_agents.sh --status     # show session status
#   ./10_claude_agents.sh --stop       # kill the entire tmux session
#   ./10_claude_agents.sh --install-cron  # add nightly restart cron job
#   ./10_claude_agents.sh --remove-cron   # remove nightly restart cron job
set -euo pipefail

SESSION="claude"
LOGFILE="$HOME/.claude/claude-agents.log"
TMUX="/usr/bin/tmux"
CLAUDE="$HOME/.local/bin/claude --model claude-sonnet-4-6"
MAX_RETRIES=5
RETRY_WAIT=1800  # 30 minutes

# WhatsApp alert config (works independently — bridge is a systemd service)
ALERT_JID="191078917525692@lid"
WA_SCRIPT="$(ls "$HOME"/.claude/plugins/cache/agentic-toolkit/whatsapp/*/scripts/wa.sh 2>/dev/null | head -1 || true)"

# Window definitions — pipe-separated: name|workdir|command[|post_cmd_1|post_cmd_2|...]
# If command starts with "claude", it's treated as a Claude instance
# (gets /exit on stop, readiness polling, post-start commands).
#
# bot    — whatsapp bot (skip permissions for autonomous operation)
# top    — crowd-top live dashboard
WINDOWS=(
  "bot|$HOME/work/bot|$CLAUDE --dangerously-skip-permissions|/loop 180s /whatsapp-check"
  "top|$HOME/work/agentic-toolkit|crowd/scripts/crowd-top"
  # "xena|$HOME/work/xena|$CLAUDE"
  # "bibi|$HOME/work/bibi|$CLAUDE"
)

# Cron markers used for idempotent install/remove
CRON_MARKER="# Claude agents nightly restart — managed by 10_claude_agents.sh"
MORNING_MARKER="# Claude agents morning greeting — managed by 10_claude_agents.sh"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$ts] $*" >> "$LOGFILE"
  echo "[$ts] $*"
}

rotate_log() {
  if [[ -f "$LOGFILE" ]]; then
    local lines
    lines=$(wc -l < "$LOGFILE")
    if (( lines > 10000 )); then
      local tmp="${LOGFILE}.tmp"
      tail -5000 "$LOGFILE" > "$tmp"
      mv "$tmp" "$LOGFILE"
      log "Log rotated (was $lines lines, kept last 5000)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# WhatsApp alert (works even when Claude is down)
# ---------------------------------------------------------------------------
send_alert() {
  local message="$1"
  if [[ -n "$WA_SCRIPT" && -f "$WA_SCRIPT" ]]; then
    bash "$WA_SCRIPT" send "$ALERT_JID" "$message" 2>/dev/null || true
    log "Sent WhatsApp alert to Mike."
  else
    log "WARNING: wa.sh not found, could not send WhatsApp alert."
  fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
parse_window() {
  IFS='|' read -ra _parts <<< "$1"
  W_NAME="${_parts[0]}"
  W_WORKDIR="${_parts[1]}"
  W_CMD="${_parts[2]}"
  W_POST_CMDS=("${_parts[@]:3}")
}

is_claude() {
  [[ "$W_CMD" == *claude* ]]
}

status() {
  if ! $TMUX has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' does not exist."
    return 1
  fi
  echo "Session: $SESSION"
  $TMUX list-windows -t "$SESSION" -F \
    '  #{window_index}: #{window_name} (#{pane_current_path}) #{?pane_dead,[dead],running} #{?window_active,← active,}'
}

jobs() {
  echo "=== Scheduled Jobs ==="
  echo ""

  # 1. System cron
  local cron
  cron=$(crontab -l 2>/dev/null | grep -v '^$' || true)
  if [[ -n "$cron" ]]; then
    echo "Cron (crontab -l):"
    echo "$cron" | while IFS= read -r line; do
      if [[ "$line" == \#* ]]; then
        echo "  $line"
      else
        # Parse cron schedule into human-readable form
        local schedule="${line%% /*}"
        local command="${line#* /}"
        local desc=""
        case "$schedule" in
          "0 3 * * *") desc="daily at 03:00" ;;
          "0 6 * * *") desc="daily at 06:00" ;;
          *)
            # minute hour dom month dow
            read -r m h dom mon dow <<< "$schedule"
            desc="cron $m $h $dom $mon $dow"
            ;;
        esac
        printf "  %-20s /%s\n" "$desc" "$command"
      fi
    done
  else
    echo "Cron: (none)"
  fi

  echo ""

  # 2. In-session loops (from WINDOWS config)
  echo "In-session loops:"
  for entry in "${WINDOWS[@]}"; do
    IFS='|' read -ra parts <<< "$entry"
    local name="${parts[0]}"
    for cmd in "${parts[@]:3}"; do
      if [[ "$cmd" == /loop* ]]; then
        local interval="${cmd#/loop }"
        interval="${interval%% *}"
        local loop_cmd="${cmd#/loop $interval }"
        printf "  %-20s %s (in %s window)\n" "every $interval" "$loop_cmd" "$name"
      fi
    done
  done

  echo ""

  # 3. Post-start commands (not loops, but run on every restart)
  echo "On restart (03:00 nightly):"
  for entry in "${WINDOWS[@]}"; do
    IFS='|' read -ra parts <<< "$entry"
    local name="${parts[0]}"
    for cmd in "${parts[@]:3}"; do
      if [[ "$cmd" != /loop* ]]; then
        printf "  %-20s %s (in %s window)\n" "once" "$cmd" "$name"
      fi
    done
  done
}

stop_session() {
  if $TMUX has-session -t "$SESSION" 2>/dev/null; then
    $TMUX kill-session -t "$SESSION"
    echo "Session '$SESSION' killed."
  else
    echo "Session '$SESSION' does not exist."
  fi
}

ensure_window() {
  mkdir -p "$W_WORKDIR"

  if ! $TMUX has-session -t "$SESSION" 2>/dev/null; then
    $TMUX new-session -d -s "$SESSION" -n "$W_NAME" -c "$W_WORKDIR"
    # Keep panes visible after process exits
    $TMUX set-option -t "$SESSION" remain-on-exit on
    log "$W_NAME: created session + window"
  elif ! $TMUX list-windows -t "$SESSION" -F '#{window_name}' | grep -qx "$W_NAME"; then
    $TMUX new-window -t "$SESSION" -n "$W_NAME" -c "$W_WORKDIR"
    log "$W_NAME: created window"
  else
    log "$W_NAME: window already exists"
  fi
}

stop_window() {
  local pane_dead pane_cmd
  pane_dead=$($TMUX list-panes -t "$SESSION:$W_NAME" -F '#{pane_dead}' 2>/dev/null || echo "")

  if [[ "$pane_dead" == "1" ]]; then
    log "$W_NAME: already stopped"
    return 0
  fi

  pane_cmd=$($TMUX list-panes -t "$SESSION:$W_NAME" -F '#{pane_current_command}' 2>/dev/null || echo "")

  if [[ "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
    log "$W_NAME: at shell prompt (nothing to stop)"
    return 0
  fi

  log "$W_NAME: stopping..."

  if is_claude; then
    # Clear any pending input, then graceful /exit
    $TMUX send-keys -t "$SESSION:$W_NAME" C-c 2>/dev/null || true
    sleep 0.5
    $TMUX send-keys -t "$SESSION:$W_NAME" "/exit" C-m

    local attempts=0
    while (( attempts < 15 )); do
      sleep 1
      pane_dead=$($TMUX list-panes -t "$SESSION:$W_NAME" -F '#{pane_dead}' 2>/dev/null || echo "")
      pane_cmd=$($TMUX list-panes -t "$SESSION:$W_NAME" -F '#{pane_current_command}' 2>/dev/null || echo "")
      if [[ "$pane_dead" == "1" || "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
        log "$W_NAME: stopped gracefully"
        return 0
      fi
      (( attempts++ )) || true
    done
    log "$W_NAME: forcing kill"
  fi

  # Ctrl-C for plain commands or as fallback for Claude
  $TMUX send-keys -t "$SESSION:$W_NAME" C-c
  sleep 1
}

start_window() {
  local pane_dead pane_cmd
  pane_dead=$($TMUX list-panes -t "$SESSION:$W_NAME" -F '#{pane_dead}' 2>/dev/null || echo "")

  if [[ "$pane_dead" == "1" ]]; then
    $TMUX respawn-pane -k -t "$SESSION:$W_NAME" "$W_CMD"
    log "$W_NAME: respawned ($W_CMD)"
  else
    pane_cmd=$($TMUX list-panes -t "$SESSION:$W_NAME" -F '#{pane_current_command}' 2>/dev/null || echo "")
    if [[ "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
      # Clear pane history so stale prompts don't confuse readiness detection
      $TMUX clear-history -t "$SESSION:$W_NAME" 2>/dev/null || true
      $TMUX send-keys -t "$SESSION:$W_NAME" "$W_CMD" C-m
      log "$W_NAME: started ($W_CMD)"
    else
      log "$W_NAME: already running ($pane_cmd)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Readiness detection & post-start
# ---------------------------------------------------------------------------

# Wait for Claude to show the ready prompt (❯) or detect auth errors.
# Returns: 0 = ready, 1 = timeout (soft fail), 2 = auth error (hard fail)
wait_for_ready() {
  local window="$1" timeout=60 elapsed=0
  local start_time
  start_time=$(date +%s)

  while (( elapsed < timeout )); do
    local pane_output
    pane_output=$($TMUX capture-pane -t "$SESSION:$window" -p -S -30 2>/dev/null || echo "")

    # Check for auth failure (hard fail)
    if echo "$pane_output" | grep -qiE \
        'OAuth token expired|authentication failed|login required|Please run.*claude auth'; then
      return 2
    fi

    # Check for ready prompt — but only if Claude has actually started
    # (look for "Claude Code" banner to avoid matching the shell prompt)
    if echo "$pane_output" | grep -q 'Claude Code'; then
      # The ❯ prompt appears mid-pane (status bar is below it)
      if echo "$pane_output" | grep -q '❯'; then
        local duration=$(( $(date +%s) - start_time ))
        log "$window: ready (${duration}s)"
        return 0
      fi
    fi

    sleep 2
    elapsed=$(( $(date +%s) - start_time ))
  done
  return 1  # timeout
}

# Send post-start commands to a Claude window.
# Returns: 0 = success, 1 = timeout (soft fail), 2 = auth error (hard fail)
post_start_window() {
  if ! is_claude; then
    return 0
  fi

  if [[ ${#W_POST_CMDS[@]} -eq 0 ]]; then
    return 0
  fi

  # Filter out empty post commands
  local cmds=()
  for cmd in "${W_POST_CMDS[@]}"; do
    [[ -n "$cmd" ]] && cmds+=("$cmd")
  done

  if [[ ${#cmds[@]} -eq 0 ]]; then
    return 0
  fi

  # Wait for Claude to start loading (replaces shell prompt)
  sleep 5

  # Wait for initial readiness
  wait_for_ready "$W_NAME"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    return $rc
  fi

  # Send each post-start command
  for cmd in "${cmds[@]}"; do
    log "$W_NAME: sending $cmd"
    $TMUX send-keys -t "$SESSION:$W_NAME" "$cmd" C-m

    # Wait for the prompt to reappear (command completed)
    # Brief pause first to let Claude start processing
    sleep 3
    wait_for_ready "$W_NAME"
    rc=$?
    if [[ $rc -ne 0 ]]; then
      log "$W_NAME: failed after sending $cmd (rc=$rc)"
      return $rc
    fi
    log "$W_NAME: $cmd done"
  done

  return 0
}

# ---------------------------------------------------------------------------
# Crowd cleanup
# ---------------------------------------------------------------------------
stop_crowd() {
  local crowd_script
  crowd_script=$(ls "$HOME"/.claude/plugins/cache/agentic-toolkit/crowd/*/scripts/crowd.sh 2>/dev/null | head -1 || true)
  if [[ -n "$crowd_script" && -f "$crowd_script" ]]; then
    log "Stopping Crowd workers..."
    bash "$crowd_script" stop-all 2>/dev/null || true
    bash "$crowd_script" cleanup 2>/dev/null || true
    log "Crowd workers cleaned up"
  fi
}

# ---------------------------------------------------------------------------
# Start/restart with post-start and retry logic
# ---------------------------------------------------------------------------
do_start() {
  local attempt="${1:-1}"

  log "--- START cycle (attempt $attempt/$MAX_RETRIES) ---"

  # Ensure all windows exist
  for entry in "${WINDOWS[@]}"; do
    parse_window "$entry"
    ensure_window
  done

  # Start each window, then immediately run post-start for Claude windows
  # (sequential per window so they don't interfere with each other)
  local failed=0
  local auth_error=0
  for entry in "${WINDOWS[@]}"; do
    parse_window "$entry"
    start_window
    if is_claude; then
      post_start_window
      local rc=$?
      if [[ $rc -eq 2 ]]; then
        # Auth error — capture pane output for the log
        local pane_output
        pane_output=$($TMUX capture-pane -t "$SESSION:$W_NAME" -p -S -30 2>/dev/null || echo "")
        log "$W_NAME: AUTH ERROR detected"
        log "Pane output: $(echo "$pane_output" | grep -iE 'auth|credential|token|login|error' | head -3)"
        auth_error=1
        break
      elif [[ $rc -ne 0 ]]; then
        log "$W_NAME: TIMEOUT waiting for ready prompt (60s)"
        failed=1
      fi
    fi
  done

  if [[ $auth_error -eq 1 ]]; then
    log "FATAL: auth failure, manual intervention required (Mike). Not retrying."
    send_alert "🚨 Claude agents restart failed: AUTH ERROR. OAuth token likely expired. Run 'claude auth login' on the server."
    return 2
  fi

  if [[ $failed -eq 1 ]]; then
    if (( attempt >= MAX_RETRIES )); then
      log "FATAL: max retries ($MAX_RETRIES) exhausted. Giving up."
      send_alert "🚨 Claude agents restart failed after $MAX_RETRIES attempts. Check server logs: $LOGFILE"
      return 1
    fi
    log "Attempt $attempt/$MAX_RETRIES failed. Retrying in $((RETRY_WAIT / 60)) minutes..."
    sleep "$RETRY_WAIT"

    # Tear down everything before retrying
    log "Tearing down for retry..."
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      stop_window
    done

    do_start $(( attempt + 1 ))
    return $?
  fi

  log "--- START cycle complete ---"
  return 0
}

do_restart() {
  rotate_log
  log "=== RESTART ==="

  # Stop Crowd workers first
  stop_crowd

  # Ensure windows exist, then stop them
  for entry in "${WINDOWS[@]}"; do
    parse_window "$entry"
    ensure_window
  done
  for entry in "${WINDOWS[@]}"; do
    parse_window "$entry"
    stop_window
  done

  # Start with post-start and retry
  do_start 1
}

# ---------------------------------------------------------------------------
# Cron management
# ---------------------------------------------------------------------------
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

install_cron() {
  local changed=0
  local current
  current=$(crontab -l 2>/dev/null || true)

  if echo "$current" | grep -qF "$CRON_MARKER"; then
    echo "Nightly restart cron already installed."
  else
    current="$current
$CRON_MARKER
0 3 * * * $SCRIPT_PATH --restart"
    changed=1
  fi

  if echo "$current" | grep -qF "$MORNING_MARKER"; then
    echo "Morning greeting cron already installed."
  else
    current="$current
$MORNING_MARKER
0 6 * * * $TMUX send-keys -t $SESSION:bot '/whatsapp-morning' C-m"
    changed=1
  fi

  if (( changed )); then
    echo "$current" | crontab -
    echo "Cron jobs installed: nightly restart at 03:00, morning greeting at 06:00 MEZ"
  fi
}

remove_cron() {
  local current
  current=$(crontab -l 2>/dev/null || true)
  if ! echo "$current" | grep -qF "$CRON_MARKER" && ! echo "$current" | grep -qF "$MORNING_MARKER"; then
    echo "No cron jobs found."
    return 0
  fi
  echo "$current" \
    | grep -vF "$CRON_MARKER" \
    | grep -v "$SCRIPT_PATH --restart" \
    | grep -vF "$MORNING_MARKER" \
    | grep -v "whatsapp-morning" \
    | crontab -
  echo "Cron jobs removed."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
# Ensure log directory exists
mkdir -p "$(dirname "$LOGFILE")"

ACTION="${1:-create}"

case "$ACTION" in
  --help|-h)
    echo "Usage: $(basename "$0") [OPTION]"
    echo ""
    echo "Manage persistent Claude Code sessions inside tmux."
    echo ""
    echo "Options:"
    echo "  (none)            Create tmux session + windows only (idempotent)"
    echo "  --start           Create, launch Claude instances, and run post-start commands"
    echo "  --restart, -r     Stop everything, then --start (with retry logic)"
    echo "  --stop, -k        Kill the entire tmux session"
    echo "  --jobs, -j        Show all scheduled and recurring jobs"
    echo "  --status, -s      Show session and window status"
    echo "  --install-cron    Add nightly restart + morning greeting cron jobs"
    echo "  --remove-cron     Remove managed cron jobs"
    echo "  --help, -h        Show this help message"
    exit 0
    ;;
  --jobs|-j)
    jobs
    exit 0
    ;;
  --status|-s)
    status
    exit 0
    ;;
  --stop|-k)
    stop_session
    exit 0
    ;;
  --restart|-r)
    do_restart
    ;;
  --start)
    log "=== START ==="
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      ensure_window
    done
    do_start 1
    ;;
  --install-cron)
    install_cron
    exit 0
    ;;
  --remove-cron)
    remove_cron
    exit 0
    ;;
  *)
    echo "Setting up tmux session '$SESSION'..."
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      ensure_window
    done
    ;;
esac

echo ""
echo "Done. Attach with: tmux attach -t $SESSION"
