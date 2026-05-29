#!/bin/bash
# Benchmark running vLLM OpenAI API (vllm bench serve).
# Usage on CT 101:
#   bench-vllm-serve.sh smoke
#   bench-vllm-serve.sh load
#   BENCH_HOST=10.x.x.101 bench-vllm-serve.sh smoke   # from another host if vllm reachable

set -euo pipefail

VLLM_BIN="${VLLM_BIN:-/opt/vllm-venv/bin/vllm}"
MODEL="${MODEL:-/srv/llm/models/Qwen3-8B-AWQ}"
HOST="${BENCH_HOST:-127.0.0.1}"
PORT="${BENCH_PORT:-8000}"
BENCH_ROOT="${BENCH_ROOT:-/srv/llm/benchmarks}"

PROFILE="${1:-smoke}"

if ! command -v "$VLLM_BIN" >/dev/null 2>&1; then
    echo "vllm not found: $VLLM_BIN" >&2
    exit 1
fi

mkdir -p "$BENCH_ROOT"
TS="$(date +%Y%m%d-%H%M)"
RESULT_DIR="${BENCH_ROOT}/${TS}-qwen3-8b-awq-${PROFILE}"
mkdir -p "$RESULT_DIR"

COMMON=(
    bench serve
    --backend openai-chat
    --host "$HOST"
    --port "$PORT"
    --endpoint /v1/chat/completions
    --model "$MODEL"
    --save-result
    --result-dir "$RESULT_DIR"
)

case "$PROFILE" in
    smoke)
        "$VLLM_BIN" "${COMMON[@]}" \
            --dataset-name random \
            --random-input-len 512 \
            --random-output-len 128 \
            --num-prompts 20 \
            --max-concurrency 1
        ;;
    load)
        "$VLLM_BIN" "${COMMON[@]}" \
            --dataset-name random \
            --random-input-len 1024 \
            --random-output-len 256 \
            --num-prompts 50 \
            --max-concurrency 5 \
            --request-rate 2 \
            --save-detailed
        ;;
    *)
        echo "Usage: $0 smoke|load" >&2
        exit 1
        ;;
esac

echo "Results dir: $RESULT_DIR"
