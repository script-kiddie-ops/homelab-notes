#!/bin/bash
# Proxmox hookscript: не более одного running гостя из group.conf
# PVE вызывает: gpu-mutex.sh <VMID> <PHASE>  (см. guest-example-hookscript.pl)

PCT=/usr/sbin/pct
QM=/usr/sbin/qm

# CLI от PVE: $1=VMID, $2=PHASE; ручной тест: env VMID/PHASE
VMID="${1:-${VMID:-}}"
PHASE="${2:-${PHASE:-}}"

[ "$PHASE" = "pre-start" ] || exit 0
[ -n "$VMID" ] || exit 0

CFG=""
for f in /etc/gpu-mutex/group.conf /etc/pve/gpu-guests/group.conf; do
    if [ -f "$f" ]; then
        CFG="$f"
        break
    fi
done

if [ -z "$CFG" ]; then
    echo "GPU mutex: нет group.conf (/etc/gpu-mutex/group.conf или /etc/pve/gpu-guests/group.conf)" >&2
    exit 1
fi

while read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [ -z "$line" ] || [[ "$line" =~ ^[0-9]+$ ]] || continue
    id="$line"
    [ "$id" = "$VMID" ] && continue
    if "$PCT" status "$id" 2>/dev/null | grep -qw running; then
        echo "GPU mutex ($CFG): CT $id already running; refusing start of $VMID" >&2
        exit 1
    fi
    if "$QM" status "$id" 2>/dev/null | grep -qw running; then
        echo "GPU mutex ($CFG): VM $id already running; refusing start of $VMID" >&2
        exit 1
    fi
done < "$CFG"
exit 0
