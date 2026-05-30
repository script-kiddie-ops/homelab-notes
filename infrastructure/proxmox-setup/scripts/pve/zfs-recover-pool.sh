#!/usr/bin/env bash
# Восстановление ZFS pool после SUSPENDED / I/O errors.
# Запуск: root на PVE — bash zfs-recover-pool.sh [pool-name]
#
# SUSPENDED + export/import часто зависает, пока CT держат datasets — скрипт
# сначала останавливает гостей на pool, затем clear; reboot — если не помогло.

set -euo pipefail

POOL="${1:-netacA}"
TIMEOUT="${ZFS_RECOVER_TIMEOUT:-120}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root." >&2
    exit 1
fi

for p in "$POOL"; do
    zpool list -H -o name "$p" &>/dev/null && POOL="$p" && break
done

echo "=== ZFS pool: $POOL ==="
zpool status -v "$POOL" || true

DISK_ID=$(zpool status -v "$POOL" 2>/dev/null | awk '/ata-|nvme-|wwn-/ {print $1; exit}')
[ -n "$DISK_ID" ] && echo "    disk: /dev/disk/by-id/$DISK_ID"

echo
echo "=== kernel (zfs / ata) ==="
dmesg 2>/dev/null | grep -iE 'zfs|ata|I/O error|'"$POOL"'' | tail -25 || true

stop_guests_on_pool() {
    echo "==> остановка CT/VM на storage $POOL"
    local conf id stor
    for conf in /etc/pve/lxc/*.conf /etc/pve/qemu/*.conf; do
        [ -f "$conf" ] || continue
        id=$(basename "$conf" .conf)
        stor=$(grep -E '^rootfs:|^scsi0:|^virtio0:' "$conf" 2>/dev/null | head -1 || true)
        [[ "$stor" == *"${POOL}"* ]] || continue
        echo "    stop VMID $id"
        pct stop "$id" 2>/dev/null || qm stop "$id" 2>/dev/null || true
    done
    sleep 3
}

write_test() {
    local ds="${POOL}/.write-test-$$"
    if zfs create -o mountpoint=none "$ds" 2>/dev/null; then
        zfs destroy "$ds"
        return 0
    fi
    return 1
}

stop_guests_on_pool

echo "==> zpool clear $POOL"
zpool clear "$POOL" 2>/dev/null || true
sleep 2

if write_test; then
    echo "OK: pool принимает запись после clear."
    zpool status "$POOL"
    exit 0
fi

STATE=$(zpool list -H -o health "$POOL" 2>/dev/null || echo UNKNOWN)
echo "WARN: запись не прошла (health=$STATE)."

if zpool status "$POOL" 2>/dev/null | grep -qi suspend; then
    echo
    echo "Pool SUSPENDED — export/import без reboot часто зависает."
    echo "Рекомендуемый порядок:"
    echo "  1. Убедитесь, что CT 100/101 остановлены: pct list"
    echo "  2. Reboot хоста:  reboot"
    echo "  3. После загрузки:"
    echo "       zpool status -v $POOL"
    echo "       zpool clear $POOL"
    echo "       smartctl -a /dev/disk/by-id/$DISK_ID   # если disk известен"
    echo "       zfs create -o mountpoint=none ${POOL}/.test && zfs destroy ${POOL}/.test"
    echo "  4. Запустите CT: pct start 101"
    echo
    echo "Пробуем export -f с timeout ${TIMEOUT}s (Ctrl+C если зависло)..."
    if timeout "$TIMEOUT" zpool export -f "$POOL" 2>/dev/null; then
        sleep 2
        timeout "$TIMEOUT" zpool import -f "$POOL" 2>/dev/null || zpool import "$POOL"
        sleep 2
        if write_test; then
            echo "OK: pool восстановлен после export/import."
            zpool status "$POOL"
            exit 0
        fi
    else
        echo "export не завершился за ${TIMEOUT}s — нужен reboot (см. выше)."
    fi
fi

echo
echo "FAIL: pool не пишет. WRITE errors на диске = проверьте SATA-кабель и SMART."
[ -n "$DISK_ID" ] && echo "  smartctl -a /dev/disk/by-id/$DISK_ID"
exit 1
