#!/bin/bash
# Spawn persistent Claude Code sessions inside tmux.
# Idempotent — safe to re-run; skips windows that are already active.
#
# When Claude exits, the pane stays visible (remain-on-exit) so you can
# read the last output. No auto-respawn — reconnect via SSH and restart
# manually with --start.
#
# Usage:
#   ./10_claude_agents.sh              # create session, no auto-start
#   ./10_claude_agents.sh --start      # create session and launch claude in each window
#   ./10_claude_agents.sh --status     # show session status
#   ./10_claude_agents.sh --stop       # kill the tmux session
set -euo pipefail

SESSION="claude"

# Window definitions: name:workdir:claude_args
# bot    — whatsapp bot (skip permissions for autonomous operation)
# kora   — remote-control agent for on-the-road work
WINDOWS=(
  "bot:$HOME/work/bot:--dangerously-skip-permissions"
  "kora:$HOME/work/kora:"
  # "xena:$HOME/work/xena:"
  # "bibi:$HOME/work/bibi:"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
status() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' does not exist."
    return 1
  fi
  echo "Session: $SESSION"
  tmux list-windows -t "$SESSION" -F \
    '  #{window_index}: #{window_name} (#{pane_current_path}) #{?pane_dead,[dead],running} #{?window_active,← active,}'
}

stop() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux kill-session -t "$SESSION"
    echo "Session '$SESSION' killed."
  else
    echo "Session '$SESSION' does not exist."
  fi
}

ensure_window() {
  local name="$1" workdir="$2"
  mkdir -p "$workdir"

  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    # First window creates the session
    tmux new-session -d -s "$SESSION" -n "$name" -c "$workdir"
    configure_session
    echo "  Created session + window '$name'"
  elif ! tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -qx "$name"; then
    tmux new-window -t "$SESSION" -n "$name" -c "$workdir"
    echo "  Created window '$name'"
  else
    echo "  Window '$name' already exists"
  fi
}

configure_session() {
  # When a pane's process exits, keep the pane visible so you can read
  # the last output. No auto-respawn — restart manually with --start.
  tmux set-option -t "$SESSION" remain-on-exit on
}

start_claude() {
  local name="$1" args="${2:-}"
  local cmd="claude${args:+ $args}"
  local pane_dead
  pane_dead=$(tmux list-panes -t "$SESSION:$name" -F '#{pane_dead}' 2>/dev/null || echo "")

  if [[ "$pane_dead" == "1" ]]; then
    # Pane is dead (previous process exited) — respawn with claude
    tmux respawn-pane -k -t "$SESSION:$name" "$cmd"
    echo "  Respawned '$name' ($cmd)"
  else
    # Pane is alive — check if it's at a shell prompt
    local pane_cmd
    pane_cmd=$(tmux list-panes -t "$SESSION:$name" -F '#{pane_current_command}' 2>/dev/null || echo "")
    if [[ "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
      tmux send-keys -t "$SESSION:$name" "$cmd" C-m
      echo "  Started '$name' ($cmd)"
    else
      echo "  Window '$name' already has a process running ($pane_cmd)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
ACTION="${1:-create}"

case "$ACTION" in
  --status|-s)
    status
    exit 0
    ;;
  --stop|-k)
    stop
    exit 0
    ;;
  --start)
    echo "Setting up tmux session '$SESSION'..."
    for entry in "${WINDOWS[@]}"; do
      IFS=: read -r name workdir args <<< "$entry"
      ensure_window "$name" "$workdir"
    done
    echo ""
    echo "Starting claude in all windows..."
    for entry in "${WINDOWS[@]}"; do
      IFS=: read -r name workdir args <<< "$entry"
      start_claude "$name" "$args"
    done
    ;;
  *)
    echo "Setting up tmux session '$SESSION'..."
    for entry in "${WINDOWS[@]}"; do
      IFS=: read -r name workdir <<< "$entry"
      ensure_window "$name" "$workdir"
    done
    ;;
esac

echo ""
echo "Done. Attach with: tmux attach -t $SESSION"
