#!/usr/bin/env bash
# Скачать основную Ollama-модель (аналог vLLM Qwen3-8B-AWQ).
# Запуск внутри CT 102 (guests) или: pct exec 102 -- bash /path/ollama-pull-default-model.sh
set -euo pipefail

MODEL="${OLLAMA_DEFAULT_MODEL:-qwen3:8b}"

echo "==> ollama pull $MODEL"
ollama pull "$MODEL"
echo "==> ollama list"
ollama list
