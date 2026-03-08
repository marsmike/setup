#!/bin/bash
# Spawn persistent Claude Code sessions inside tmux.
# Idempotent — safe to re-run; skips windows that are already active.
#
# Auto-restart: uses tmux remain-on-exit + respawn-pane so you always see
# Claude's actual UI. When Claude exits, the pane shows its last output for
# RESPAWN_DELAY seconds, then automatically respawns.
#
# Usage:
#   ./10_claude_agents.sh              # create session, no auto-start
#   ./10_claude_agents.sh --start      # create session and launch claude in each window
#   ./10_claude_agents.sh --status     # show session status
#   ./10_claude_agents.sh --stop       # kill the tmux session
set -euo pipefail

SESSION="claude"
RESPAWN_DELAY=10

# Window definitions: name:workdir
WINDOWS=(
  "bot:$HOME/work/bot"
  "kora:$HOME/work/kora"
  "xena:$HOME/work/xena"
  "bibi:$HOME/work/bibi"
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
  # When a pane's process exits, keep the pane visible (shows last output)
  tmux set-option -t "$SESSION" remain-on-exit on

  # Auto-respawn dead panes after a delay
  # The hook fires whenever a pane dies; we sleep then respawn it
  tmux set-hook -t "$SESSION" pane-died \
    "run-shell 'sleep ${RESPAWN_DELAY} && tmux respawn-pane -k -t \"#{session_name}:#{window_name}\"'"
}

start_claude() {
  local name="$1"
  local pane_dead
  pane_dead=$(tmux list-panes -t "$SESSION:$name" -F '#{pane_dead}' 2>/dev/null || echo "")

  if [[ "$pane_dead" == "1" ]]; then
    # Pane is dead (previous process exited) — respawn with claude
    tmux respawn-pane -k -t "$SESSION:$name" "claude"
    echo "  Respawned claude in '$name'"
  else
    # Pane is alive — check if it's at a shell prompt
    local pane_cmd
    pane_cmd=$(tmux list-panes -t "$SESSION:$name" -F '#{pane_current_command}' 2>/dev/null || echo "")
    if [[ "$pane_cmd" == "bash" || "$pane_cmd" == "zsh" ]]; then
      tmux send-keys -t "$SESSION:$name" "claude" C-m
      echo "  Started claude in '$name'"
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
      IFS=: read -r name workdir <<< "$entry"
      ensure_window "$name" "$workdir"
    done
    echo ""
    echo "Starting claude in all windows..."
    for entry in "${WINDOWS[@]}"; do
      IFS=: read -r name workdir <<< "$entry"
      start_claude "$name"
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
