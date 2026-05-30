#!/usr/bin/env bash
# Развёртывание LLM-GPU CT из template 900 — один проход.
#
# Usage (root на PVE, cd ~/llm-gpu-setup):
#   bash scripts/pve/deploy-llm-ct.sh --engine ollama
#   bash scripts/pve/deploy-llm-ct.sh --vmid 103 --hostname guests-sglang-ct --ip 10.x.x.103/24 --engine none
#   DESTROY_YES=1 bash scripts/pve/deploy-llm-ct.sh --engine ollama   # пересоздать CT
#
# Переменные (pve-deploy.env или env):
#   DEPLOY_VMID, DEPLOY_HOSTNAME, DEPLOY_IP, DEPLOY_GW, TEMPLATE_VMID=900
#   LLM_PVE_HOME, LLM_SSH_USER, LLM_SSH_PORT
#   OLLAMA_* — legacy aliases для --engine ollama (102 по умолчанию)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEPLOY_ENV="${LLM_GPU_DEPLOY_ENV:-$BASE/pve-deploy.env}"

if [ -f "$DEPLOY_ENV" ]; then
    # shellcheck disable=SC1090
    set -a && source "$DEPLOY_ENV" && set +a
fi

TEMPLATE_VMID="${TEMPLATE_VMID:-900}"
DEPLOY_VMID="${DEPLOY_VMID:-${OLLAMA_VMID:-102}}"
DEPLOY_HOSTNAME="${DEPLOY_HOSTNAME:-${OLLAMA_HOSTNAME:-guests-ollama-ct}}"
DEPLOY_IP="${DEPLOY_IP:-${OLLAMA_IP:-10.x.x.102/24}}"
DEPLOY_GW="${DEPLOY_GW:-${OLLAMA_GW:-10.x.x.1}}"
LLM_PVE_HOME="${LLM_PVE_HOME:-/home/guests}"
LLM_SSH_USER="${LLM_SSH_USER:-guests}"
LLM_SSH_PORT="${LLM_SSH_PORT:-1234}"
ENGINE="${ENGINE:-none}"
REGISTRY="${LLM_GPU_REGISTRY:-/etc/llm-gpu/clones.registry}"

usage() {
    echo "Usage: $0 [--vmid N] [--hostname NAME] [--ip CIDR] [--gw IP] [--engine ollama|none]" >&2
    echo "  DESTROY_YES=1  — удалить существующий VMID перед deploy" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --vmid) DEPLOY_VMID="$2"; shift 2 ;;
        --hostname) DEPLOY_HOSTNAME="$2"; shift 2 ;;
        --ip) DEPLOY_IP="$2"; shift 2 ;;
        --gw) DEPLOY_GW="$2"; shift 2 ;;
        --engine) ENGINE="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown arg: $1" >&2; usage ;;
    esac
done

DEPLOY_IP_HOST="${DEPLOY_IP%%/*}"
ENGINE_TAG="$ENGINE"
[ "$ENGINE" = ollama ] && ENGINE_TAG=ollama

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root на хосте Proxmox." >&2
    exit 1
fi

if ! pct config "$TEMPLATE_VMID" &>/dev/null; then
    echo "Template VMID $TEMPLATE_VMID не найден. Сначала: bash RUN_AS_ROOT.sh template" >&2
    exit 1
fi

destroy_existing() {
    local vmid="$1"
    if ! pct status "$vmid" &>/dev/null && [ ! -f "/etc/pve/lxc/${vmid}.conf" ]; then
        return 0
    fi
    echo "==> destroy existing CT $vmid"
    pct stop "$vmid" 2>/dev/null || true
    pct destroy "$vmid"
    if [ -f "$REGISTRY" ]; then
        grep -vE "^[[:space:]]*${vmid}[[:space:]]" "$REGISTRY" | grep -vE "^${vmid}[[:space:]]" >"${REGISTRY}.tmp" || true
        mv "${REGISTRY}.tmp" "$REGISTRY"
    fi
    if [ -f /etc/gpu-mutex/group.conf ]; then
        grep -vE "^[[:space:]]*${vmid}[[:space:]]*$" /etc/gpu-mutex/group.conf | grep -vE "^${vmid}[[:space:]]*$" > /tmp/gpu-group.$$
        mv /tmp/gpu-group.$$ /etc/gpu-mutex/group.conf
    fi
}

stop_gpu_peers() {
    local vmid="$1"
    while read -r line || [ -n "$line" ]; do
        line="${line%%#*}"
        line="${line//[[:space:]]/}"
        [[ "$line" =~ ^[0-9]+$ ]] || continue
        id="$line"
        [[ "$id" == "$vmid" ]] && continue
        if pct status "$id" 2>/dev/null | grep -qw running; then
            echo "==> pct stop $id (GPU mutex — старт $vmid)"
            pct stop "$id"
        fi
    done < /etc/gpu-mutex/group.conf 2>/dev/null || true
}

sync_ct_ssh_keys() {
    local vmid="$1"
    local keys="${LLM_PVE_HOME}/.ssh/authorized_keys"
    if [ ! -s "$keys" ]; then
        echo "WARN: $keys пуст — SSH в CT настройте вручную (см. 03c-deploy-llm-gpu-clone.md)" >&2
        return 0
    fi
    echo "==> SSH: sync authorized_keys → CT $vmid (user $LLM_SSH_USER)"
    pct push "$vmid" "$keys" /tmp/llm-authorized_keys
    pct exec "$vmid" -- bash -c "
        install -d -m 700 -o ${LLM_SSH_USER} -g ${LLM_SSH_USER} /home/${LLM_SSH_USER}/.ssh
        install -m 600 -o ${LLM_SSH_USER} -g ${LLM_SSH_USER} /tmp/llm-authorized_keys /home/${LLM_SSH_USER}/.ssh/authorized_keys
        rm -f /tmp/llm-authorized_keys
        systemctl restart ssh
    "
}

verify_deploy() {
    local vmid="$1"
    local ip="$2"
    echo "=== verify CT $vmid ==="
    pct exec "$vmid" -- nvidia-smi | head -5
    pct exec "$vmid" -- ls /srv/llm/models 2>/dev/null | head -3 || true

    if [ "$ENGINE" = ollama ]; then
        pct exec "$vmid" -- systemctl is-active ollama
        pct exec "$vmid" -- curl -sf "http://127.0.0.1:11434/" >/dev/null && echo "Ollama API (localhost): OK"
        curl -sf "http://${ip}:11434/" >/dev/null && echo "Ollama API (LAN ${ip}): OK" || \
            echo "WARN: LAN curl failed — проверьте CT running и OLLAMA_HOST=0.0.0.0" >&2
    fi

    if pct status "$vmid" 2>/dev/null | grep -qw running; then
        /var/lib/vz/snippets/gpu-mutex.sh 101 pre-start >/dev/null 2>&1
        rc=$?
        if [ "$rc" -eq 1 ]; then
            echo "GPU mutex (peer blocked while $vmid running): OK"
        else
            echo "WARN: mutex test exit=$rc" >&2
        fi
    fi
    echo "=== verify done ==="
}

# --- main ---

if [ "${DESTROY_YES:-0}" = 1 ]; then
    destroy_existing "$DEPLOY_VMID"
fi

if pct status "$DEPLOY_VMID" &>/dev/null || [ -f "/etc/pve/lxc/${DEPLOY_VMID}.conf" ]; then
    echo "VMID $DEPLOY_VMID уже существует. DESTROY_YES=1 для пересоздания." >&2
    exit 1
fi

if [ "$ENGINE" = ollama ]; then
    mkdir -p /mnt/llm-shared/ollama
    chmod 755 /mnt/llm-shared/ollama
fi

echo "==> clone $TEMPLATE_VMID → $DEPLOY_VMID ($DEPLOY_HOSTNAME, engine=$ENGINE_TAG)"
bash "$SCRIPT_DIR/clone-llm-gpu-ct.sh" "$DEPLOY_VMID" "$DEPLOY_HOSTNAME" "$ENGINE_TAG" "$TEMPLATE_VMID"

CONF="/etc/pve/lxc/${DEPLOY_VMID}.conf"
if grep -qE '^net0:' "$CONF"; then
    sed -i "s|^net0:.*|net0: name=eth0,bridge=vmbr0,gw=${DEPLOY_GW},ip=${DEPLOY_IP},type=veth|" "$CONF"
else
    echo "net0: name=eth0,bridge=vmbr0,gw=${DEPLOY_GW},ip=${DEPLOY_IP},type=veth" >>"$CONF"
fi

stop_gpu_peers "$DEPLOY_VMID"

echo "==> pct start $DEPLOY_VMID"
pct start "$DEPLOY_VMID"
sleep 6

sync_ct_ssh_keys "$DEPLOY_VMID"

case "$ENGINE" in
    ollama)
        bash "$SCRIPT_DIR/install-ollama-engine.sh" "$DEPLOY_VMID"
        ;;
    none)
        echo "==> engine none — установите движок вручную внутри CT"
        ;;
    *)
        echo "Unknown engine: $ENGINE" >&2
        exit 1
        ;;
esac

verify_deploy "$DEPLOY_VMID" "$DEPLOY_IP_HOST"

# убрать stale test-clone 899 если остался
if [ -f "$REGISTRY" ]; then
    grep -vE '^899[[:space:]]' "$REGISTRY" > "${REGISTRY}.tmp" || true
    mv "${REGISTRY}.tmp" "$REGISTRY"
fi

echo
echo "=== CT $DEPLOY_VMID ($DEPLOY_HOSTNAME) готов ==="
echo "SSH: ssh -p ${LLM_SSH_PORT} ${LLM_SSH_USER}@${DEPLOY_IP_HOST}"
[ "$ENGINE" = ollama ] && echo "Ollama: http://${DEPLOY_IP_HOST}:11434"
echo "Пароли: pct exec ${DEPLOY_VMID} -- passwd ${LLM_SSH_USER}"
[ "$ENGINE" = ollama ] && echo "Модель: ssh ${LLM_SSH_USER}@${DEPLOY_IP_HOST} → ollama pull qwen3:8b (см. 05-ollama-operations.md)"
