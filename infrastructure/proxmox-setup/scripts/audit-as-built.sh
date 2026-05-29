#!/usr/bin/env bash
# Read-only snapshot of PVE host + CT 101 for docs. Run on laptop:
#   ./scripts/audit-as-built.sh
# Requires ~/.ssh/config hosts: guests-pve, guests-101 (key auth).

set -euo pipefail
SSH_OPTS=(-F "${HOME}/.ssh/config" -o BatchMode=yes -o ConnectTimeout=10)

run_host() {
  ssh "${SSH_OPTS[@]}" guests-pve 'bash -s' <<'EOF'
echo "=== PVE HOST ==="
hostname; date -Is
ip -4 -br addr | grep -v '^lo'
pveversion 2>/dev/null || true
zpool list 2>/dev/null || true
zfs list -r netacA 2>/dev/null | head -20 || true
nvidia-smi 2>/dev/null | head -12 || echo "(no nvidia-smi)"
EOF
}

run_ct() {
  ssh "${SSH_OPTS[@]}" guests-101 'bash -s' <<'EOF'
echo "=== CT 101 ==="
hostname; date -Is
ip -4 -br addr | grep eth0 || true
nvidia-smi 2>/dev/null | head -12 || echo "(no nvidia-smi)"
systemctl is-active vllm 2>/dev/null || true
/opt/vllm-venv/bin/pip show vllm 2>/dev/null | grep -E '^Version:' || true
df -h / /srv/llm 2>/dev/null || true
ls /srv/llm/models 2>/dev/null || true
EOF
}

run_host
echo
run_ct
