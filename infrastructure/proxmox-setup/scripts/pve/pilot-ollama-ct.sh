#!/usr/bin/env bash
# Фаза C: clone template 900 → CT 102 + Ollama + registry + mutex.
# Запуск: root на PVE — bash pilot-ollama-ct.sh
#
# Переменные:
#   OLLAMA_VMID=102
#   OLLAMA_HOSTNAME=guests-ollama-ct
#   OLLAMA_IP=10.x.x.102/24
#   OLLAMA_GW=10.x.x.1
#   TEMPLATE_VMID=900

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OLLAMA_VMID="${OLLAMA_VMID:-102}"
OLLAMA_HOSTNAME="${OLLAMA_HOSTNAME:-guests-ollama-ct}"
OLLAMA_IP="${OLLAMA_IP:-10.x.x.102/24}"
OLLAMA_GW="${OLLAMA_GW:-10.x.x.1}"
TEMPLATE_VMID="${TEMPLATE_VMID:-900}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root на хосте Proxmox." >&2
    exit 1
fi

mkdir -p /mnt/llm-shared/ollama
chmod 755 /mnt/llm-shared/ollama

if ! pct config "$TEMPLATE_VMID" &>/dev/null; then
    echo "Template VMID $TEMPLATE_VMID не найден. Сначала: bash create-llm-gpu-template.sh" >&2
    exit 1
fi

bash "$SCRIPT_DIR/clone-llm-gpu-ct.sh" "$OLLAMA_VMID" "$OLLAMA_HOSTNAME" ollama "$TEMPLATE_VMID"

CONF="/etc/pve/lxc/${OLLAMA_VMID}.conf"
if grep -qE '^net0:' "$CONF"; then
    sed -i "s|^net0:.*|net0: name=eth0,bridge=vmbr0,gw=${OLLAMA_GW},ip=${OLLAMA_IP},type=veth|" "$CONF"
else
    echo "net0: name=eth0,bridge=vmbr0,gw=${OLLAMA_GW},ip=${OLLAMA_IP},type=veth" >>"$CONF"
fi

# GPU mutex: остановить других из group.conf (обычно 101) перед стартом 102
GPU_STOPPED=()
while read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ "$line" =~ ^[0-9]+$ ]] || continue
    id="$line"
    [[ "$id" == "$OLLAMA_VMID" ]] && continue
    if pct status "$id" 2>/dev/null | grep -qw running; then
        echo "==> pct stop $id (GPU mutex — старт $OLLAMA_VMID)"
        GPU_STOPPED+=("$id")
        pct stop "$id"
    fi
done < /etc/gpu-mutex/group.conf 2>/dev/null || true

echo "==> pct start $OLLAMA_VMID"
pct start "$OLLAMA_VMID"
sleep 6

echo "==> install Ollama"
pct exec "$OLLAMA_VMID" -- bash -c 'curl -fsSL https://ollama.com/install.sh | sh'

pct exec "$OLLAMA_VMID" -- mkdir -p /etc/systemd/system/ollama.service.d
pct exec "$OLLAMA_VMID" -- tee /etc/systemd/system/ollama.service.d/override.conf >/dev/null <<'EOF'
[Service]
Environment="OLLAMA_MODELS=/srv/llm/ollama"
EOF

pct exec "$OLLAMA_VMID" -- systemctl daemon-reload
pct exec "$OLLAMA_VMID" -- systemctl enable --now ollama

echo "==> verify"
pct exec "$OLLAMA_VMID" -- nvidia-smi 2>/dev/null | head -4 || true
pct exec "$OLLAMA_VMID" -- systemctl is-active ollama
pct exec "$OLLAMA_VMID" -- ls /srv/llm/models 2>/dev/null | head -3 || true

echo
echo "=== CT $OLLAMA_VMID ($OLLAMA_HOSTNAME) готов ==="
echo "SSH: ssh -p 1234 guests@${OLLAMA_IP%%/*}"
echo "Ollama: http://${OLLAMA_IP%%/*}:11434"
