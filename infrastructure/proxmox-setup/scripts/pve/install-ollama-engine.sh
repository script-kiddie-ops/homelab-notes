#!/usr/bin/env bash
# Установка Ollama внутри LLM-GPU CT (после clone). Root на PVE.
# Usage: install-ollama-engine.sh <vmid>
set -euo pipefail

VMID="${1:?Usage: $0 <vmid>}"

echo "==> prerequisites (zstd for ollama install.sh)"
pct exec "$VMID" -- bash -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y zstd'

echo "==> install Ollama"
pct exec "$VMID" -- bash -c 'curl -fsSL https://ollama.com/install.sh | sh'

pct exec "$VMID" -- mkdir -p /srv/llm/ollama
pct exec "$VMID" -- chown ollama:ollama /srv/llm/ollama

pct exec "$VMID" -- mkdir -p /etc/systemd/system/ollama.service.d
pct exec "$VMID" -- tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="OLLAMA_MODELS=/srv/llm/ollama"
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

pct exec "$VMID" -- systemctl daemon-reload
pct exec "$VMID" -- systemctl enable ollama
pct exec "$VMID" -- systemctl restart ollama
sleep 2

echo "==> ollama: $(pct exec "$VMID" -- systemctl is-active ollama)"
