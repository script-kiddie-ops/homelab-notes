#!/usr/bin/env bash
# Клонирование CT из template 900 + регистрация в registry + GPU mutex + tag.
#
# Usage (root на PVE):
#   clone-llm-gpu-ct.sh <new-vmid> <hostname> <engine> [template-vmid]
#
# Пример:
#   clone-llm-gpu-ct.sh 102 guests-ollama-ct ollama
#
# После clone отредактируйте net0 в /etc/pve/lxc/<vmid>.conf (IP, gw).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${LLM_GPU_REGISTRY:-/etc/llm-gpu/clones.registry}"
REGISTRY_SRC="$SCRIPT_DIR/llm-gpu-clones.registry"
TEMPLATE_VMID="${4:-900}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root на хосте Proxmox." >&2
    exit 1
fi

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <new-vmid> <hostname> <engine> [template-vmid]" >&2
    exit 1
fi

NEW_VMID="$1"
HOSTNAME="$2"
ENGINE="$3"
DATE="$(date +%Y-%m-%d)"

mkdir -p /etc/llm-gpu
if [ ! -f "$REGISTRY" ]; then
    cp "$REGISTRY_SRC" "$REGISTRY"
    echo "Создан $REGISTRY"
fi

if pct status "$NEW_VMID" &>/dev/null || [ -f "/etc/pve/lxc/${NEW_VMID}.conf" ]; then
    echo "VMID $NEW_VMID уже занят." >&2
    exit 1
fi

echo "==> pct clone $TEMPLATE_VMID $NEW_VMID --hostname $HOSTNAME --full 1"
pct clone "$TEMPLATE_VMID" "$NEW_VMID" --hostname "$HOSTNAME" --full 1

CONF="/etc/pve/lxc/${NEW_VMID}.conf"
FRAG="$SCRIPT_DIR/llm-gpu-base.conf.fragment"

# Template без mp0 — дописать shared storage + GPU из fragment
while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    case "$line" in
        mp0:*|hookscript:*|features:*|lxc.*)
            grep -qF "$line" "$CONF" 2>/dev/null || echo "$line" >>"$CONF"
            ;;
    esac
done <"$FRAG"

if ! grep -qE '^tags:.*llm-gpu-base' "$CONF" 2>/dev/null; then
    if grep -qE '^tags:' "$CONF"; then
        sed -i 's/^tags:.*/&,llm-gpu-base/' "$CONF"
    else
        echo "tags: llm-gpu-base" >>"$CONF"
    fi
fi

# GPU mutex: hookscript + VMID в group.conf
if [ -f "$SCRIPT_DIR/install-gpu-mutex.sh" ]; then
    bash "$SCRIPT_DIR/install-gpu-mutex.sh" "$NEW_VMID" || true
elif ! grep -qE '^hookscript:[[:space:]]*local:snippets/gpu-mutex\.sh' "$CONF"; then
    echo "hookscript: local:snippets/gpu-mutex.sh" >>"$CONF"
fi

GROUP_CONF="/etc/gpu-mutex/group.conf"
mkdir -p /etc/gpu-mutex
if [ ! -f "$GROUP_CONF" ] && [ -f "$SCRIPT_DIR/gpu-guests-group.conf" ]; then
    cp "$SCRIPT_DIR/gpu-guests-group.conf" "$GROUP_CONF"
fi
if [ -f "$GROUP_CONF" ] && \
   ! grep -qE "^[[:space:]]*${NEW_VMID}[[:space:]]*$" "$GROUP_CONF" && \
   ! grep -qE "^${NEW_VMID}[[:space:]]*$" "$GROUP_CONF"; then
    echo "$NEW_VMID" >>"$GROUP_CONF"
    echo "Добавлен VMID $NEW_VMID в $GROUP_CONF"
fi

if ! grep -qE "^[[:space:]]*${NEW_VMID}[[:space:]]" "$REGISTRY" && \
   ! grep -qE "^${NEW_VMID}[[:space:]]" "$REGISTRY"; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$NEW_VMID" "$HOSTNAME" "$ENGINE" "$TEMPLATE_VMID" "$DATE" >>"$REGISTRY"
    echo "Добавлено в $REGISTRY"
fi

echo
echo "==> Clone готов. Дальше:"
echo "  1. Правка $CONF — net0 (IP, gw, hwaddr)"
echo "  2. pct start $NEW_VMID"
echo "  3. Установка engine ($ENGINE) внутри CT"
