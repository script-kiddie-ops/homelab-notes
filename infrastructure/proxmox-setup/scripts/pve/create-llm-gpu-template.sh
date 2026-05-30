#!/usr/bin/env bash
# Создание CT 900 и конвертация в template llm-gpu-base.
# Запуск: root на PVE — bash create-llm-gpu-template.sh
#
# Переменные окружения (опционально):
#   TEMPLATE_VMID=900
#   ZFS_POOL=netacA          имя ZFS-пула (на бою задайте реальное, см. private/map)
#   CT_PASSWORD=              пароль root CT (если пуст — без пароля, только ключи после bootstrap)
#   SKIP_TEMPLATE=0           1 = только создать CT, не конвертировать
#   ROOTFS_STORAGE=           storage для rootfs (default: ZFS pool; при проблемах ZFS: local)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CT_SCRIPTS="$SCRIPT_DIR/../ct"
TEMPLATE_VMID="${TEMPLATE_VMID:-900}"
SKIP_TEMPLATE="${SKIP_TEMPLATE:-0}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root на хосте Proxmox." >&2
    exit 1
fi

bash "$SCRIPT_DIR/host-prep-check.sh"

# Pool (ZFS_POOL или autodetect netacA; на бою — pve-deploy.env)
detect_zfs_pool() {
    local p
    for p in ${ZFS_POOL:+"$ZFS_POOL"} netacA; do
        zpool list -H -o name "$p" &>/dev/null && echo "$p" && return 0
    done
    return 1
}
ZFS_POOL="${ZFS_POOL:-}"
if [ -z "$ZFS_POOL" ]; then
    ZFS_POOL="$(detect_zfs_pool)" || true
fi
[ -n "$ZFS_POOL" ] || {
    echo "ZFS pool не найден. Создайте ~/llm-gpu-setup/pve-deploy.env с ZFS_POOL=… (см. scripts/pve/pve-deploy.env.example)." >&2
    exit 1
}

# ZFS pool must accept I/O (not SUSPENDED / DEGRADED without recovery)
ZFS_HEALTH="$(zpool list -H -o health "$ZFS_POOL" 2>/dev/null || echo UNKNOWN)"
if [ "$ZFS_HEALTH" != "ONLINE" ]; then
    echo "ZFS pool $ZFS_POOL: health=$ZFS_HEALTH (нужен ONLINE)." >&2
    echo "Выполните: zpool status -v $ZFS_POOL && bash $SCRIPT_DIR/zfs-recover-pool.sh $ZFS_POOL" >&2
    exit 1
fi
if zpool status "$ZFS_POOL" 2>/dev/null | grep -qiE 'suspend|faulted|unavail'; then
    echo "ZFS pool $ZFS_POOL: I/O suspended или ошибка — см. zpool status -v $ZFS_POOL" >&2
    echo "Восстановление: bash $SCRIPT_DIR/zfs-recover-pool.sh $ZFS_POOL" >&2
    exit 1
fi
# пробная запись в pool (list может работать при suspended writes)
if ! zfs create -o mountpoint=none "${ZFS_POOL}/.llm-gpu-write-test-$$" 2>/dev/null; then
    echo "ZFS pool $ZFS_POOL не принимает запись (I/O suspended?)." >&2
    echo "Восстановление: bash $SCRIPT_DIR/zfs-recover-pool.sh $ZFS_POOL" >&2
    exit 1
fi
zfs destroy "${ZFS_POOL}/.llm-gpu-write-test-$$" 2>/dev/null || true

ROOTFS_STORAGE="${ROOTFS_STORAGE:-$ZFS_POOL}"
if [ "$ROOTFS_STORAGE" != "$ZFS_POOL" ]; then
    echo "WARN: rootfs на $ROOTFS_STORAGE (не $ZFS_POOL) — аварийный режим при проблемах ZFS" >&2
fi

# OS template (pveam list: колонка 1 — local:vztmpl/…tar.zst, колонка 2 — SIZE)
OSTEMPLATE=$(pveam list local 2>/dev/null | awk '/ubuntu-24.04-standard/ {
  if ($1 ~ /^local:vztmpl\//) { print $1; exit }
  for (i = 1; i <= NF; i++) if ($i ~ /\.tar\.zst$/) { print "local:vztmpl/" $i; exit }
}')
[ -n "$OSTEMPLATE" ] || { echo "Скачайте ubuntu-24.04-standard: pveam download local ubuntu-24.04-standard_24.04-2_amd64.tar.zst" >&2; exit 1; }
echo "    ostemplate: $OSTEMPLATE"

if pct status "$TEMPLATE_VMID" &>/dev/null 2>&1 || [ -f "/etc/pve/lxc/${TEMPLATE_VMID}.conf" ]; then
    if grep -qE '^template:\s*1' "/etc/pve/lxc/${TEMPLATE_VMID}.conf" 2>/dev/null; then
        echo "VMID $TEMPLATE_VMID уже template. Пересборка: bash $SCRIPT_DIR/recreate-llm-gpu-template.sh" >&2
        exit 1
    fi
    echo "==> resume: CT $TEMPLATE_VMID уже создан, пропуск pct create"
    RESUME=1
else
    RESUME=0
fi

# SSH keys с хоста для bootstrap
AUTH_KEYS=""
PVE_HOME="${LLM_PVE_HOME:-/home/guests}"
for k in /root/.ssh/authorized_keys "${PVE_HOME}/.ssh/authorized_keys"; do
    [ -s "$k" ] && AUTH_KEYS="$k" && break
done
[ -n "$AUTH_KEYS" ] || echo "WARN: authorized_keys не найден ($PVE_HOME или /root) — SSH user в CT настроите вручную." >&2

echo "==> pct create $TEMPLATE_VMID"
CREATE_ARGS=(
    "$TEMPLATE_VMID" "$OSTEMPLATE"
    --hostname llm-gpu-base
    --cores 8 --memory 65536 --swap 8192
    --rootfs "${ROOTFS_STORAGE}:64"
    --unprivileged 0
    --features nesting=1
    --mp0 /mnt/llm-shared,mp=/srv/llm
    --net0 "name=eth0,bridge=vmbr0,ip=dhcp"
    --ostype ubuntu
    --onboot 0
)
[ -n "${CT_PASSWORD:-}" ] && CREATE_ARGS+=(--password "$CT_PASSWORD")
if [ "${RESUME:-0}" -eq 0 ]; then
    pct create "${CREATE_ARGS[@]}"
fi

CONF="/etc/pve/lxc/${TEMPLATE_VMID}.conf"
FRAG="$SCRIPT_DIR/llm-gpu-base.conf.fragment"

if [ "${RESUME:-0}" -eq 0 ]; then
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue
        case "$line" in
            arch:*|cores:*|memory:*|swap:*|ostype:*|features:*|mp0:*|hookscript:*|tags:*)
                grep -qF "$line" "$CONF" 2>/dev/null || echo "$line" >>"$CONF"
                ;;
            lxc.*)
                grep -qF "$line" "$CONF" 2>/dev/null || echo "$line" >>"$CONF"
                ;;
        esac
    done <"$FRAG"
fi

bash "$SCRIPT_DIR/install-gpu-mutex.sh" 2>/dev/null || true

# Одна 3060: пока в group.conf кто-то running (101), hookscript не даст стартовать 900.
# Template один раз запускаем для bootstrap, затем pct template — в эксплуатации не стартует.
GPU_STOPPED=()
stop_gpu_group_members() {
    local cfg=/etc/gpu-mutex/group.conf
    [[ -f "$cfg" ]] || return 0
    while read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [[ "$line" =~ ^[0-9]+$ ]] || continue
        local id="$line"
        [[ "$id" == "$TEMPLATE_VMID" ]] && continue
        if pct status "$id" 2>/dev/null | grep -qw running; then
            echo "==> pct stop $id (освободить GPU для сборки template $TEMPLATE_VMID)"
            GPU_STOPPED+=("$id")
            pct stop "$id"
        fi
    done <"$cfg"
}

start_stopped_gpu_guests() {
    local id
    for id in "${GPU_STOPPED[@]}"; do
        echo "==> pct start $id"
        pct start "$id" || true
    done
}

stop_gpu_group_members

echo "==> pct start $TEMPLATE_VMID"
if ! pct start "$TEMPLATE_VMID"; then
    start_stopped_gpu_guests
    exit 1
fi
sleep 8

echo "==> push bootstrap scripts"
pct exec "$TEMPLATE_VMID" -- mkdir -p /root/llm-gpu-scripts /root/.llm-bootstrap
for f in bootstrap-llm-gpu-base.sh sanitize-for-template.sh upgrade-nvidia-user-space.sh; do
    pct push "$TEMPLATE_VMID" "$CT_SCRIPTS/$f" "/root/llm-gpu-scripts/$f"
    pct exec "$TEMPLATE_VMID" -- chmod +x "/root/llm-gpu-scripts/$f"
done
[ -n "$AUTH_KEYS" ] && pct push "$TEMPLATE_VMID" "$AUTH_KEYS" /root/.llm-bootstrap/authorized_keys

echo "==> bootstrap inside CT"
HOST_DRIVER="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')"
[ -n "$HOST_DRIVER" ] || { echo "nvidia-smi на хосте недоступен." >&2; exit 1; }
echo "    host driver: $HOST_DRIVER"
LLM_SSH_USER="${LLM_SSH_USER:-guests}"
LLM_SSH_PORT="${LLM_SSH_PORT:-1234}"
pct exec "$TEMPLATE_VMID" -- env LLM_NVIDIA_DRIVER_VERSION="$HOST_DRIVER" \
    LLM_SSH_USER="$LLM_SSH_USER" LLM_SSH_PORT="$LLM_SSH_PORT" \
    LLM_AUTHORIZED_KEYS=/root/.llm-bootstrap/authorized_keys \
    bash /root/llm-gpu-scripts/bootstrap-llm-gpu-base.sh

echo "==> verify"
if ! pct exec "$TEMPLATE_VMID" -- nvidia-smi >/dev/null 2>&1; then
    echo "FAIL: nvidia-smi в CT $TEMPLATE_VMID не работает." >&2
    pct exec "$TEMPLATE_VMID" -- nvidia-smi 2>&1 || true
    start_stopped_gpu_guests
    exit 1
fi
pct exec "$TEMPLATE_VMID" -- nvidia-smi 2>/dev/null | head -5 || true
pct exec "$TEMPLATE_VMID" -- ls /srv/llm/models 2>/dev/null | head -5 || true

echo "==> sanitize"
pct exec "$TEMPLATE_VMID" -- bash /root/llm-gpu-scripts/sanitize-for-template.sh

pct stop "$TEMPLATE_VMID"

if [ "$SKIP_TEMPLATE" -eq 1 ]; then
    start_stopped_gpu_guests
    echo "SKIP_TEMPLATE=1 — CT $TEMPLATE_VMID создан, не конвертирован в template."
    exit 0
fi

# Proxmox: bind mount mp0 на host path нельзя оставить в template
if grep -qE '^mp0:' "$CONF"; then
    echo "==> убрать mp0 из $CONF перед pct template (bind /mnt/llm-shared добавят clone-скрипт)"
    sed -i '/^mp0:/d' "$CONF"
fi

echo "==> pct template $TEMPLATE_VMID"
if ! pct template "$TEMPLATE_VMID"; then
    echo "FAIL: pct template $TEMPLATE_VMID" >&2
    start_stopped_gpu_guests
    exit 1
fi

if grep -qE '^template:\s*1' "$CONF" 2>/dev/null; then
    echo "OK: VMID $TEMPLATE_VMID — template"
else
    echo "WARN: проверьте в GUI/pct list, что $TEMPLATE_VMID — template" >&2
fi

start_stopped_gpu_guests

# Registry dir on host
mkdir -p /etc/llm-gpu
[ -f /etc/llm-gpu/clones.registry ] || cp "$SCRIPT_DIR/llm-gpu-clones.registry" /etc/llm-gpu/clones.registry

echo
echo "=== Template $TEMPLATE_VMID (llm-gpu-base) готов ==="
echo "Clone: bash $SCRIPT_DIR/clone-llm-gpu-ct.sh <vmid> <hostname> <engine>"
