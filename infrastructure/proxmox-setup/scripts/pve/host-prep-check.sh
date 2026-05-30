#!/usr/bin/env bash
# Фаза A: проверка предусловий на хосте PVE перед созданием template 900.
# Запуск: root на PVE — bash host-prep-check.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
ok=0
fail=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        echo -e "${GREEN}OK${NC}  $desc"
        ok=$((ok + 1))
    else
        echo -e "${RED}FAIL${NC}  $desc" >&2
        fail=$((fail + 1))
    fi
}

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root на хосте Proxmox." >&2
    exit 1
fi

echo "=== LLM GPU template — host prep ==="
echo

# ZFS pool / llm-shared
POOL=""
for p in ${ZFS_POOL:+"$ZFS_POOL"} netacA; do
    if zpool list -H -o name "$p" &>/dev/null; then
        POOL="$p"
        break
    fi
done
check "ZFS pool найден (${POOL:-нет})" [ -n "$POOL" ]

LLM_DS=""
for ds in "${POOL}/llm-shared" "llm-shared"; do
    if zfs list "$ds" &>/dev/null; then
        LLM_DS="$ds"
        break
    fi
done
# dataset мог быть создан с другим именем — ищем по mountpoint
if [ -z "$LLM_DS" ]; then
    LLM_DS="$(zfs list -H -o name,mountpoint 2>/dev/null | awk '$2=="/mnt/llm-shared" {print $1; exit}')"
fi
if [ -z "$LLM_DS" ]; then
    LLM_DS="$(findmnt -n -o SOURCE --target /mnt/llm-shared 2>/dev/null || true)"
fi

MNT="/mnt/llm-shared"
if [ -n "$LLM_DS" ]; then
    check "dataset / shared storage ($LLM_DS)" true
elif [ -d "$MNT/models" ]; then
    echo -e "${GREEN}OK${NC}  shared storage ($MNT — bind mount, ZFS dataset llm-shared не найден по имени)"
    ok=$((ok + 1))
else
    check "dataset llm-shared или $MNT/models" false
fi

check "mountpoint $MNT существует" [ -d "$MNT" ]
check "каталог models в shared storage" [ -d "$MNT/models" ]

# GPU
check "nvidia-smi на хосте" command -v nvidia-smi >/dev/null 2>&1
if command -v nvidia-smi &>/dev/null; then
    echo "--- nvidia-smi (host) ---"
    nvidia-smi 2>/dev/null | head -5 || true
fi
check "/dev/nvidia0" [ -e /dev/nvidia0 ]
check "/dev/nvidia-uvm" [ -e /dev/nvidia-uvm ]

echo "--- GPU device majors (для conf.fragment) ---"
ls -l /dev/nvidia* 2>/dev/null || true

# GPU mutex
check "hookscript snippet" [ -f /var/lib/vz/snippets/gpu-mutex.sh ]
check "gpu-mutex group.conf" [ -f /etc/gpu-mutex/group.conf ]
if [ -f /etc/gpu-mutex/group.conf ]; then
    echo "--- group.conf ---"
    grep -v '^[[:space:]]*#' /etc/gpu-mutex/group.conf | grep -E '[0-9]+' || true
fi

# Template / CT 900
if pct status 900 &>/dev/null; then
    echo "WARN: VMID 900 уже существует: $(pct status 900)"
elif pvesh get "/nodes/$(hostname)/lxc/900/config" &>/dev/null 2>&1; then
    echo "INFO: VMID 900 существует (template или CT)"
else
    echo "INFO: VMID 900 свободен — можно создавать template"
fi

# Ubuntu template
TEMPL=$(pveam list local 2>/dev/null | awk '/ubuntu-24.04-standard/ {
  if ($1 ~ /^local:vztmpl\//) { sub(/^local:vztmpl\//, "", $1); print $1; exit }
  for (i = 1; i <= NF; i++) if ($i ~ /\.tar\.zst$/) { print $i; exit }
}')
check "ubuntu-24.04 CT template в local" [ -n "${TEMPL:-}" ]
[ -n "${TEMPL:-}" ] && echo "    template: local:vztmpl/$TEMPL"

echo
echo "=== Итог: OK=$ok FAIL=$fail ==="
[ "$fail" -eq 0 ]
