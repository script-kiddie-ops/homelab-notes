#!/usr/bin/env bash
# Довести CT 900 до template после частичного create (nvidia mismatch / pct template failed).
# Запуск: root на PVE — bash fix-template-900.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_VMID="${TEMPLATE_VMID:-900}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root." >&2
    exit 1
fi

if grep -qE '^template:\s*1' "/etc/pve/lxc/${TEMPLATE_VMID}.conf" 2>/dev/null; then
    echo "VMID $TEMPLATE_VMID уже template."
    exit 0
fi

if ! [ -f "/etc/pve/lxc/${TEMPLATE_VMID}.conf" ]; then
    echo "Нет CT $TEMPLATE_VMID — сначала create-llm-gpu-template.sh" >&2
    exit 1
fi

HOST_DRIVER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | tr -d ' ')"
echo "Host driver: $HOST_DRIVER"

# stop GPU guests
while read -r line; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    id="$line"
    [[ "$id" == "$TEMPLATE_VMID" ]] && continue
    pct status "$id" 2>/dev/null | grep -qw running && pct stop "$id"
done < /etc/gpu-mutex/group.conf 2>/dev/null || true

pct start "$TEMPLATE_VMID"
for _ in $(seq 1 30); do
    pct status "$TEMPLATE_VMID" 2>/dev/null | grep -qw running && break
    sleep 1
done
pct status "$TEMPLATE_VMID" | grep -qw running || { echo "CT $TEMPLATE_VMID не running." >&2; exit 1; }

CT_SCRIPTS="$SCRIPT_DIR/../ct"
pct exec "$TEMPLATE_VMID" -- mkdir -p /root/llm-gpu-scripts
for f in bootstrap-llm-gpu-base.sh sanitize-for-template.sh; do
    [ -f "$CT_SCRIPTS/$f" ] || { echo "Нет $CT_SCRIPTS/$f" >&2; exit 1; }
    pct push "$TEMPLATE_VMID" "$CT_SCRIPTS/$f" "/root/llm-gpu-scripts/$f"
    pct exec "$TEMPLATE_VMID" -- chmod +x "/root/llm-gpu-scripts/$f"
done
pct exec "$TEMPLATE_VMID" -- env LLM_NVIDIA_DRIVER_VERSION="$HOST_DRIVER" \
    bash /root/llm-gpu-scripts/bootstrap-llm-gpu-base.sh --upgrade-only

pct exec "$TEMPLATE_VMID" -- nvidia-smi | head -5

pct exec "$TEMPLATE_VMID" -- bash /root/llm-gpu-scripts/sanitize-for-template.sh 2>/dev/null \
    || pct exec "$TEMPLATE_VMID" -- bash -c 'apt clean; rm -f /root/.bash_history'

pct stop "$TEMPLATE_VMID"
CONF="/etc/pve/lxc/${TEMPLATE_VMID}.conf"
sed -i '/^mp0:/d' "$CONF"

pct template "$TEMPLATE_VMID"
grep -qE '^template:\s*1' "$CONF" && echo "OK: template $TEMPLATE_VMID"

pct start 101 2>/dev/null || true
echo "Готово. Deploy: bash $SCRIPT_DIR/deploy-llm-ct.sh --engine ollama"
