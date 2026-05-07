#!/bin/bash
# benchmark_llm.sh — Inference speed benchmark for Ollama models on F3A
# Tests tokens/sec via Ollama API for each loaded model.
set -euo pipefail

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
PROMPT="${BENCHMARK_PROMPT:-"Explain the difference between a CPU and a GPU in exactly three sentences."}"
RESULTS_FILE="${HOME}/benchmark-results-$(date +%Y%m%d-%H%M%S).txt"

# ANSI colours
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()    { echo -e "${BLUE}[benchmark]${NC} $*"; }
result() { echo -e "${GREEN}[result]${NC}   $*"; }
warn()   { echo -e "${YELLOW}[warn]${NC}     $*"; }

# Require: curl, python3, jq (optional)
for dep in curl python3; do
  command -v "$dep" >/dev/null 2>&1 || { echo "ERROR: $dep is required"; exit 1; }
done

# ─── Header ───────────────────────────────────────────────────────────────────
{
echo "====================================="
echo "  LLM Benchmark — $(date)"
echo "  Host: $(hostname)"
echo "  Prompt: ${PROMPT:0:60}..."
echo "====================================="
echo ""
} | tee "$RESULTS_FILE"

# ─── List available models ─────────────────────────────────────────────────────
log "Fetching model list from Ollama..."
MODELS_JSON=$(curl -sf "${OLLAMA_URL}/api/tags" 2>/dev/null) || { warn "Ollama not reachable at ${OLLAMA_URL}"; exit 1; }
MODELS=$(echo "$MODELS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
models = [m['name'] for m in data.get('models', [])]
# Skip embedding-only models (bge, nomic-embed, etc.)
models = [m for m in models if not any(x in m.lower() for x in ['bge', 'embed', 'nomic'])]
print('\n'.join(models))
")

if [ -z "$MODELS" ]; then
  warn "No inference models found in Ollama. Install a model first: ollama pull gemma3:27b-it-q4_K_M"
  exit 1
fi

log "Models to benchmark:"
echo "$MODELS" | while read -r m; do log "  - $m"; done
echo "" | tee -a "$RESULTS_FILE"

# ─── Benchmark each model ──────────────────────────────────────────────────────
benchmark_model() {
  local model="$1"
  log "Benchmarking: ${model}"

  local start end elapsed
  start=$(date +%s%N)

  local response
  response=$(curl -sf "${OLLAMA_URL}/api/generate" \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
print(json.dumps({
  'model': '$model',
  'prompt': '''$PROMPT''',
  'stream': False,
  'options': {'num_predict': 150, 'temperature': 0.1}
}))
")" 2>/dev/null) || { warn "  ERROR: inference failed for ${model}"; return; }

  end=$(date +%s%N)
  elapsed=$(( (end - start) / 1000000 ))  # ms

  local eval_count eval_duration prompt_eval_count prompt_eval_duration
  eval_count=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_count', 0))")
  eval_duration=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('eval_duration', 1))")
  prompt_eval_count=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt_eval_count', 0))")
  prompt_eval_duration=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prompt_eval_duration', 1))")

  # Ollama reports duration in nanoseconds
  local gen_tps prompt_tps
  gen_tps=$(python3 -c "print(f'{${eval_count} * 1e9 / max(${eval_duration}, 1):.1f}')")
  prompt_tps=$(python3 -c "print(f'{${prompt_eval_count} * 1e9 / max(${prompt_eval_duration}, 1):.1f}')")

  local answer
  answer=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response','').strip()[:200])")

  {
  echo "─────────────────────────────────────"
  echo "Model:         ${model}"
  echo "Prompt tokens: ${prompt_eval_count}   (${prompt_tps} tok/s)"
  echo "Output tokens: ${eval_count}   (${gen_tps} tok/s)  ← generation speed"
  echo "Wall time:     ${elapsed} ms"
  echo "Answer:        ${answer:0:150}..."
  echo ""
  } | tee -a "$RESULTS_FILE"

  result "${model}: ${gen_tps} tok/s generation  |  ${prompt_tps} tok/s prompt"
}

echo "$MODELS" | while read -r model; do
  [ -n "$model" ] && benchmark_model "$model"
done

# ─── GPU info ─────────────────────────────────────────────────────────────────
{
echo "─────────────────────────────────────"
echo "GPU:"
rocm-smi --showuse 2>/dev/null | grep -E "(GPU|Use)" | head -6 || nvidia-smi --query-gpu=name,utilization.gpu,memory.used --format=csv,noheader 2>/dev/null | head -4 || echo "  (rocm-smi / nvidia-smi not available)"
echo ""
echo "Results saved to: ${RESULTS_FILE}"
echo "====================================="
} | tee -a "$RESULTS_FILE"

log "Done. Full results: ${RESULTS_FILE}"
