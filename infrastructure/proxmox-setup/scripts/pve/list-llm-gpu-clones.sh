#!/usr/bin/env bash
# Список VMID CT, клонированных из template llm-gpu-base (900).
# Запуск на PVE: bash list-llm-gpu-clones.sh [--verify-tags]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${LLM_GPU_REGISTRY:-/etc/llm-gpu/clones.registry}"
[ -f "$REGISTRY" ] || REGISTRY="$SCRIPT_DIR/llm-gpu-clones.registry"

VERIFY_TAGS=0
[ "${1:-}" = "--verify-tags" ] && VERIFY_TAGS=1

if [ ! -f "$REGISTRY" ]; then
    echo "Registry не найден: $REGISTRY" >&2
    exit 1
fi

while read -r vmid hostname engine from date _; do
    [[ "$vmid" =~ ^[0-9]+$ ]] || continue
    echo "$vmid"
    if [ "$VERIFY_TAGS" -eq 1 ] && [ -f "/etc/pve/lxc/${vmid}.conf" ]; then
        if ! grep -qE '^tags:.*llm-gpu-base' "/etc/pve/lxc/${vmid}.conf" 2>/dev/null; then
            echo "WARN: VMID $vmid без tag llm-gpu-base" >&2
        fi
    fi
done < <(grep -v '^[[:space:]]*#' "$REGISTRY" | grep -E '^[0-9]+')
