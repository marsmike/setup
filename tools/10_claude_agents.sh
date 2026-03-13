#!/bin/bash
# Spawn persistent Claude Code sessions inside tmux.
# Idempotent — safe to re-run; skips windows that are already active.
#
# When Claude exits, the pane stays visible (remain-on-exit) so you can
# read the last output. No auto-respawn — reconnect via SSH and restart
# manually with --start or --restart.
#
# Usage:
#   ./10_claude_agents.sh              # create session + windows only
#   ./10_claude_agents.sh --start      # create and launch (skip running)
#   ./10_claude_agents.sh --restart    # stop running instances, then start fresh
#   ./10_claude_agents.sh --status     # show session status
#   ./10_claude_agents.sh --stop       # kill the entire tmux session
set -euo pipefail

SESSION="claude"

# Window definitions — pipe-separated: name|workdir|command
# If command starts with "claude", it's treated as a Claude instance
# (gets /exit on stop). Otherwise it's a plain command (gets Ctrl-C).
#
# bot    — whatsapp bot (skip permissions for autonomous operation)
# kora   — remote-control agent for on-the-road work
# top    — crowd-top live dashboard
WINDOWS=(
  "bot|$HOME/work/bot|claude --dangerously-skip-permissions"
  "kora|$HOME/work/kora|claude"
  "top|$HOME/work/agentic-toolkit|crowd/scripts/crowd-top"
  # "xena|$HOME/work/xena|claude"
  # "bibi|$HOME/work/bibi|claude"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
parse_window() {
  # Parse pipe-separated window definition
  IFS='|' read -r W_NAME W_WORKDIR W_CMD <<< "$1"
}

is_claude() {
  [[ "$W_CMD" == claude* ]]
}

status() {
  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' does not exist."
    return 1
  fi
  echo "Session: $SESSION"
  tmux list-windows -t "$SESSION" -F \
    '  #{window_index}: #{window_name} (#{pane_current_path}) #{?pane_dead,[dead],running} #{?window_active,← active,}'
}

stop_session() {
  if tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux kill-session -t "$SESSION"
    echo "Session '$SESSION' killed."
  else
    echo "Session '$SESSION' does not exist."
  fi
}

ensure_window() {
  mkdir -p "$W_WORKDIR"

  if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    tmux new-session -d -s "$SESSION" -n "$W_NAME" -c "$W_WORKDIR"
    # Keep panes visible after process exits
    tmux set-option -t "$SESSION" remain-on-exit on
    echo "  Created session + window '$W_NAME'"
  elif ! tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -qx "$W_NAME"; then
    tmux new-window -t "$SESSION" -n "$W_NAME" -c "$W_WORKDIR"
    echo "  Created window '$W_NAME'"
  else
    echo "  Window '$W_NAME' already exists"
  fi
}

stop_window() {
  local pane_dead pane_cmd
  pane_dead=$(tmux list-panes -t "$SESSION:$W_NAME" -F '#{pane_dead}' 2>/dev/null || echo "")

  if [[ "$pane_dead" == "1" ]]; then
    echo "  '$W_NAME' already stopped"
    return 0
  fi

  pane_cmd=$(tmux list-panes -t "$SESSION:$W_NAME" -F '#{pane_current_command}' 2>/dev/null || echo "")

  if [[ "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
    echo "  '$W_NAME' at shell prompt (nothing to stop)"
    return 0
  fi

  echo -n "  Stopping '$W_NAME'..."

  if is_claude; then
    # Graceful: send /exit to Claude
    tmux send-keys -t "$SESSION:$W_NAME" "/exit" C-m

    local attempts=0
    while (( attempts < 15 )); do
      sleep 1
      pane_dead=$(tmux list-panes -t "$SESSION:$W_NAME" -F '#{pane_dead}' 2>/dev/null || echo "")
      pane_cmd=$(tmux list-panes -t "$SESSION:$W_NAME" -F '#{pane_current_command}' 2>/dev/null || echo "")
      if [[ "$pane_dead" == "1" || "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
        echo " done"
        return 0
      fi
      (( attempts++ ))
    done
    echo " forcing kill"
  fi

  # Ctrl-C for plain commands or as fallback for Claude
  tmux send-keys -t "$SESSION:$W_NAME" C-c
  sleep 1
}

start_window() {
  local pane_dead pane_cmd
  pane_dead=$(tmux list-panes -t "$SESSION:$W_NAME" -F '#{pane_dead}' 2>/dev/null || echo "")

  if [[ "$pane_dead" == "1" ]]; then
    tmux respawn-pane -k -t "$SESSION:$W_NAME" "$W_CMD"
    echo "  Respawned '$W_NAME' ($W_CMD)"
  else
    pane_cmd=$(tmux list-panes -t "$SESSION:$W_NAME" -F '#{pane_current_command}' 2>/dev/null || echo "")
    if [[ "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
      tmux send-keys -t "$SESSION:$W_NAME" "$W_CMD" C-m
      echo "  Started '$W_NAME' ($W_CMD)"
    else
      echo "  '$W_NAME' already running ($pane_cmd)"
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
    stop_session
    exit 0
    ;;
  --restart|-r)
    echo "Restarting tmux session '$SESSION'..."
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      ensure_window
    done
    echo ""
    echo "Stopping running instances..."
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      stop_window
    done
    echo ""
    echo "Starting all windows..."
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      start_window
    done
    ;;
  --start)
    echo "Setting up tmux session '$SESSION'..."
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      ensure_window
    done
    echo ""
    echo "Starting all windows..."
    for entry in "${WINDOWS[@]}"; do
      parse_window "$entry"
      start_window
    done
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
