#!/usr/bin/env bash
# Скачать основную модель Ollama (аналог vLLM Qwen3-8B-AWQ) и smoke-test.
# Запуск на PVE root: bash scripts/ct/ollama-setup-primary-model.sh [vmid]
# Или внутри CT: bash /path/to/ollama-setup-primary-model.sh
set -euo pipefail

VMID="${1:-}"
MODEL="${OLLAMA_PRIMARY_MODEL:-qwen3:8b}"
PROMPT="${OLLAMA_TEST_PROMPT:-Скажи одно слово: ping}"

run_in_ct() {
    if [ -n "$VMID" ]; then
        pct exec "$VMID" -- bash -s <<EOF
set -euo pipefail
MODEL="$MODEL"
PROMPT="$PROMPT"
$(declare -f pull_and_test)
pull_and_test
EOF
    else
        pull_and_test
    fi
}

pull_and_test() {
    echo "==> ollama pull $MODEL (blobs → /srv/llm/ollama)"
    ollama pull "$MODEL"

    echo "==> ollama list"
    ollama list

    echo "==> API generate test"
    curl -sf "http://127.0.0.1:11434/api/generate" -d "$(jq -nc \
        --arg model "$MODEL" --arg prompt "$PROMPT" \
        '{model: $model, prompt: $prompt, stream: false}')" | jq -r '.response // .' | head -5

    echo "==> nvidia-smi"
    nvidia-smi | head -8

    echo "=== OK: $MODEL ==="
}

if [ "$(id -u)" -ne 0 ] && [ -z "$VMID" ]; then
    echo "Внутри CT запускайте как обычный user (guests) с доступом к ollama." >&2
fi

run_in_ct
