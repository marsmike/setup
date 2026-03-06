#!/bin/bash
# Spawn persistent Claude Code remote-control sessions inside tmux.
# Idempotent — safe to re-run; skips sessions that are already active.
set -euo pipefail

SESSION="claude"
AGENTS=("kora" "xena" "bibi")
WORKDIRS=("$HOME/work/kora" "$HOME/work/xena" "$HOME/work/bibi")

# Ensure work directories exist
for dir in "${WORKDIRS[@]}"; do
  mkdir -p "$dir"
done

# Create tmux session with first agent if it doesn't exist
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Creating tmux session '$SESSION'..."
  tmux new-session -d -s "$SESSION" -n "${AGENTS[0]}" -c "${WORKDIRS[0]}"
  tmux send-keys -t "$SESSION:${AGENTS[0]}" \
    "while true; do claude remote-control --name ${AGENTS[0]}; sleep 5; done" C-m

  # Create remaining agent windows
  for i in $(seq 1 $((${#AGENTS[@]} - 1))); do
    tmux new-window -t "$SESSION" -n "${AGENTS[$i]}" -c "${WORKDIRS[$i]}"
    tmux send-keys -t "$SESSION:${AGENTS[$i]}" \
      "while true; do claude remote-control --name ${AGENTS[$i]}; sleep 5; done" C-m
  done

  echo "Started ${#AGENTS[@]} agents: ${AGENTS[*]}"
else
  echo "Tmux session '$SESSION' already exists."

  # Check each agent window, create if missing
  for i in "${!AGENTS[@]}"; do
    if ! tmux list-windows -t "$SESSION" -F '#{window_name}' | grep -qx "${AGENTS[$i]}"; then
      echo "Adding missing window '${AGENTS[$i]}'..."
      tmux new-window -t "$SESSION" -n "${AGENTS[$i]}" -c "${WORKDIRS[$i]}"
      tmux send-keys -t "$SESSION:${AGENTS[$i]}" \
        "while true; do claude remote-control --name ${AGENTS[$i]}; sleep 5; done" C-m
    else
      echo "Agent '${AGENTS[$i]}' already running."
    fi
  done
fi

echo "Done. Attach with: tmux attach -t $SESSION"
