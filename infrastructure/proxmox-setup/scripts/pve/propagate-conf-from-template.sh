#!/usr/bin/env bash
# Пропагация propagatable полей из llm-gpu-base.conf.fragment в .conf указанных CT.
#
# Usage (root на PVE):
#   propagate-conf-from-template.sh [--dry-run] [--include-resources] [VMID ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENT="$SCRIPT_DIR/llm-gpu-base.conf.fragment"
DRY_RUN=0
INCLUDE_RESOURCES=0
VMIDS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --include-resources) INCLUDE_RESOURCES=1 ;;
        -h|--help)
            echo "Usage: $0 [--dry-run] [--include-resources] [VMID ...]"
            exit 0
            ;;
        *) VMIDS+=("$1") ;;
    esac
    shift
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root на хосте Proxmox." >&2
    exit 1
fi

[ -f "$FRAGMENT" ] || { echo "Fragment не найден: $FRAGMENT" >&2; exit 1; }

if [ "${#VMIDS[@]}" -eq 0 ]; then
    mapfile -t VMIDS < <(bash "$SCRIPT_DIR/list-llm-gpu-clones.sh" 2>/dev/null || true)
fi
[ "${#VMIDS[@]}" -gt 0 ] || { echo "Нет VMID." >&2; exit 1; }

is_propagatable() {
    local line="$1"
    case "$line" in
        lxc.mount.entry:*|lxc.cgroup2.devices.allow:*|mp0:*|hookscript:*|features:*) return 0 ;;
        memory:*|cores:*|swap:*)
            [ "$INCLUDE_RESOURCES" -eq 1 ] && return 0
            return 1
            ;;
        *) return 1 ;;
    esac
}

merge_conf() {
    local conf="$1"
    local tmp
    tmp="$(mktemp)"

    while IFS= read -r line || [ -n "$line" ]; do
        if is_propagatable "$line"; then
            continue
        fi
        printf '%s\n' "$line"
    done <"$conf" >"$tmp"

    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        is_propagatable "$line" && printf '%s\n' "$line" >>"$tmp"
    done <"$FRAGMENT"

    echo "$tmp"
}

for vmid in "${VMIDS[@]}"; do
    conf="/etc/pve/lxc/${vmid}.conf"
    [ -f "$conf" ] || { echo "SKIP $vmid: нет conf" >&2; continue; }
    echo "=== VMID $vmid ==="
    merged="$(merge_conf "$conf")"
    if [ "$DRY_RUN" -eq 1 ]; then
        diff -u "$conf" "$merged" || true
        rm -f "$merged"
    else
        bak="${conf}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$conf" "$bak"
        mv "$merged" "$conf"
        echo "OK $conf (backup $bak)"
    fi
done

[ "$DRY_RUN" -eq 0 ] && echo "Перезапуск: pct stop <VMID> && pct start <VMID> (по одному, GPU mutex)"
