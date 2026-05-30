#!/usr/bin/env bash
# Полная пересборка template 900: destroy → create с нуля.
# Запуск: root на PVE — bash recreate-llm-gpu-template.sh
#
#   RECREATE_YES=1 bash recreate-llm-gpu-template.sh   # без интерактива

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMPLATE_VMID="${TEMPLATE_VMID:-900}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root." >&2
    exit 1
fi

if [ -f "$ROOT/pve-deploy.env" ]; then
    # shellcheck disable=SC1091
    set -a && source "$ROOT/pve-deploy.env" && set +a
elif [ -f "$ROOT/../pve-deploy.env" ]; then
    set -a && source "$ROOT/../pve-deploy.env" && set +a
fi

if [ "${RECREATE_YES:-0}" != 1 ]; then
    echo "Будет удалён VMID $TEMPLATE_VMID (CT или template) и создан заново."
    echo "vLLM (101) на время сборки будет остановлен create-скриптом."
    printf 'Подтвердите (yes): '
    read -r ans
    [ "$ans" = yes ] || { echo "Отменено."; exit 1; }
fi

if pct status "$TEMPLATE_VMID" &>/dev/null 2>&1 || [ -f "/etc/pve/lxc/${TEMPLATE_VMID}.conf" ]; then
    echo "==> pct stop $TEMPLATE_VMID"
    pct stop "$TEMPLATE_VMID" 2>/dev/null || true
    echo "==> pct destroy $TEMPLATE_VMID"
    pct destroy "$TEMPLATE_VMID"
    sleep 2
fi

echo "==> create-llm-gpu-template.sh (clean)"
exec bash "$SCRIPT_DIR/create-llm-gpu-template.sh"
