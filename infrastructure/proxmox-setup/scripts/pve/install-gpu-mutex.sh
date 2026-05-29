#!/bin/bash
# Установка GPU mutex hook на узле Proxmox VE (запуск: root на host).
# Пример: bash install-gpu-mutex.sh 101
#         bash install-gpu-mutex.sh 101 102

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUP_CONF="/etc/gpu-mutex/group.conf"
LEGACY_GROUP_CONF="/etc/pve/gpu-guests/group.conf"
SNIPPET="/var/lib/vz/snippets/gpu-mutex.sh"
HOOK_REF="local:snippets/gpu-mutex.sh"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root на хосте Proxmox (su -)." >&2
    exit 1
fi
if [ ! -d /etc/pve ]; then
    echo "Нет /etc/pve — это не узел PVE." >&2
    exit 1
fi

# group.conf — на обычной ФС (/etc/gpu-mutex), не под pmxcfs: install/chmod в /etc/pve/* часто падают
mkdir -p /etc/gpu-mutex /var/lib/vz/snippets

if [ -f "$LEGACY_GROUP_CONF" ]; then
    cp "$LEGACY_GROUP_CONF" "$GROUP_CONF"
    echo "Синхронизирован $LEGACY_GROUP_CONF → $GROUP_CONF"
elif [ ! -f "$GROUP_CONF" ]; then
    cp "$SCRIPT_DIR/gpu-guests-group.conf" "$GROUP_CONF"
    echo "Создан $GROUP_CONF"
else
    echo "Оставлен $GROUP_CONF"
fi

cp "$SCRIPT_DIR/gpu-mutex.sh" "$SNIPPET"
chmod 755 "$SNIPPET"
echo "Установлен $SNIPPET"

if [ "$#" -eq 0 ]; then
    set -- 101
fi

attach_hook() {
    local vmid="$1"
    local conf lxc qemu

    lxc="/etc/pve/lxc/${vmid}.conf"
    qemu="/etc/pve/qemu/${vmid}.conf"

    if [ -f "$lxc" ]; then
        conf="$lxc"
    elif [ -f "$qemu" ]; then
        conf="$qemu"
    else
        echo "Пропуск VMID $vmid: нет $lxc или $qemu" >&2
        return 1
    fi

    if grep -qE '^hookscript:[[:space:]]*local:snippets/gpu-mutex\.sh' "$conf"; then
        echo "VMID $vmid: hookscript уже в $conf"
        return 0
    fi

    if grep -qE '^hookscript:' "$conf"; then
        echo "VMID $vmid: в $conf уже другой hookscript — добавьте вручную: hookscript: $HOOK_REF" >&2
        return 1
    fi

    echo "hookscript: $HOOK_REF" >>"$conf"
    echo "VMID $vmid: добавлен hookscript в $conf"
}

failed=0
for vmid in "$@"; do
    attach_hook "$vmid" || failed=1
done

echo
echo "Проверка:"
ls -l "$SNIPPET" "$GROUP_CONF"
echo "--- group.conf ---"
grep -v '^[[:space:]]*#' "$GROUP_CONF" | grep -E '[0-9]+' || true
echo "--- hook в conf ---"
for vmid in "$@"; do
    for f in "/etc/pve/lxc/${vmid}.conf" "/etc/pve/qemu/${vmid}.conf"; do
        [ -f "$f" ] && grep -E '^hookscript:' "$f" || true
    done
done

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo
echo "Ручной тест (на host, при running 100) — как вызывает Proxmox:"
echo "  $SNIPPET 101 pre-start; echo exit=\$?"
echo "  # exit=1 — mutex сработал; затем pct start 101 / GUI Start — тоже отказ"
echo
echo "Опционально: mkdir -p /etc/gpu-mutex && cp $GROUP_CONF /etc/gpu-mutex/  # единый путь"
