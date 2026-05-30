#!/usr/bin/env bash
# Bootstrap CT «llm-gpu-base»: NVIDIA user-space, HF paths, базовые пакеты, SSH user.
# Запуск внутри CT под root:
#   bash bootstrap-llm-gpu-base.sh
#   bash bootstrap-llm-gpu-base.sh --upgrade-only   # только NVIDIA libs (Runbook 2)
#
# Опции окружения:
#   LLM_SSH_USER=guests          пользователь SSH (default: guests)
#   LLM_SSH_PORT=1234           порт sshd (default: 1234)
#   LLM_AUTHORIZED_KEYS=        путь к authorized_keys
#   LLM_NVIDIA_DRIVER_VERSION=  версия с хоста PVE (напр. 595.71.05); обязательна при сборке template

set -euo pipefail

UPGRADE_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --upgrade-only) UPGRADE_ONLY=1 ;;
        -h|--help)
            echo "Usage: bootstrap-llm-gpu-base.sh [--upgrade-only]"
            exit 0
            ;;
    esac
done

LLM_SSH_USER="${LLM_SSH_USER:-guests}"
LLM_SSH_PORT="${LLM_SSH_PORT:-1234}"

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root внутри CT." >&2
    exit 1
fi

log() { echo "==> $*"; }

install_cuda_repo() {
    if [ -f /usr/share/keyrings/cuda-archive-keyring.gpg ]; then
        log "CUDA keyring уже установлен"
        return 0
    fi
    log "Установка CUDA apt keyring (debian13)"
    apt-get update -qq
    apt-get install -y wget ca-certificates
    local deb=/tmp/cuda-keyring.deb
    wget -qO "$deb" \
        "https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/cuda-keyring_1.1-1_all.deb"
    dpkg -i "$deb"
    rm -f "$deb"
}

nvidia_pkg_versions() {
    # madison: "pkg | version | repo" — версия между '|', не $2 при FS по пробелам
    apt-cache madison "$1" 2>/dev/null | awk -v v="$2" -F'|' '
        {
            ver = $2
            gsub(/^[ \t]+|[ \t]+$/, "", ver)
            if (ver ~ "^" v) { print ver; exit }
        }'
}

purge_nvidia_user_space() {
    log "Удаление NVIDIA/CUDA user-space (смена версии или повторная установка)"
    rm -f /etc/apt/preferences.d/llm-nvidia-driver-pin
    apt-mark showhold 2>/dev/null | grep -E '^(libnvidia|nvidia-|libcuda)' | xargs -r apt-mark unhold || true
    local pkgs
    pkgs=$(dpkg-query -W -f='${Package}\n' 2>/dev/null \
        | grep -E '^(libnvidia|nvidia-|libcuda|libcudadebugger|libnvcuvid|libnvoptix)' || true)
    if [ -n "$pkgs" ]; then
        # shellcheck disable=SC2086
        DEBIAN_FRONTEND=noninteractive apt-get remove -y --purge $pkgs
        apt-get autoremove -y
    fi
}

write_nvidia_version_pin() {
    local ver="$1"
    cat >/etc/apt/preferences.d/llm-nvidia-driver-pin <<EOF
# Временно: не тянуть 610.x при установке ${ver} (CUDA repo default = newest)
Package: libnvidia-*
Pin: version ${ver}*
Pin-Priority: 1001

Package: nvidia-*
Pin: version ${ver}*
Pin-Priority: 1001

Package: libcuda*
Pin: version ${ver}*
Pin-Priority: 1001

Package: libcudadebugger*
Pin: version ${ver}*
Pin-Priority: 1001

Package: libnvcuvid*
Pin: version ${ver}*
Pin-Priority: 1001

Package: libnvoptix*
Pin: version ${ver}*
Pin-Priority: 1001
EOF
}

install_nvidia_user_space() {
    install_cuda_repo
    local ver="${LLM_NVIDIA_DRIVER_VERSION:-}"
    [ -n "$ver" ] || ver="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')"
    if [ -z "$ver" ]; then
        echo "Задайте LLM_NVIDIA_DRIVER_VERSION (версия с хоста: nvidia-smi на PVE)." >&2
        exit 1
    fi

    log "Установка NVIDIA user-space ${ver} (как на хосте PVE), без nvidia-kernel-dkms"
    apt-mark showhold 2>/dev/null | grep -E '^(libnvidia|nvidia-)' | xargs -r apt-mark unhold || true
    apt-get update -qq

    local drv_ver
    drv_ver=$(nvidia_pkg_versions nvidia-driver-cuda "$ver")

    if [ -z "$drv_ver" ]; then
        echo "В CUDA repo нет пакетов для драйвера ${ver}. В CT: apt-cache madison nvidia-driver-cuda | grep ${ver}" >&2
        exit 1
    fi

    local installed_ml=""
    installed_ml=$(dpkg-query -W -f='${Version}\n' libnvidia-ml1 2>/dev/null || true)
    if [ -n "$installed_ml" ] && [[ "$installed_ml" != "${ver}"* ]]; then
        log "Сейчас libnvidia-ml1=${installed_ml}, нужна ${ver}*"
        purge_nvidia_user_space
        apt-get update -qq
    fi

    log "Метапакет nvidia-driver-cuda=${drv_ver} (+ pin ${ver}*, иначе apt выберет 610)"
    write_nvidia_version_pin "$ver"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades -o APT::Install-Recommends=false \
        "nvidia-driver-cuda=${drv_ver}"
    rm -f /etc/apt/preferences.d/llm-nvidia-driver-pin

    local got_ml got_cuda
    got_ml=$(dpkg-query -W -f='${Version}\n' libnvidia-ml1 2>/dev/null || true)
    got_cuda=$(dpkg-query -W -f='${Version}\n' libcuda1 2>/dev/null || true)
    if [[ "$got_ml" != "${ver}"* ]] || [[ "$got_cuda" != "${ver}"* ]]; then
        echo "После install: libnvidia-ml1=${got_ml:-—} libcuda1=${got_cuda:-—}, ожидалось ${ver}*" >&2
        exit 1
    fi

    log "Проверка nvidia-smi"
    if ! nvidia-smi >/dev/null 2>&1; then
        nvidia-smi 2>&1 || true
        echo "nvidia-smi FAILED — версия libs должна совпасть с драйвером хоста (${ver})." >&2
        exit 1
    fi
    nvidia-smi 2>/dev/null | head -5 || true

    log "apt-mark hold на libnvidia-* / nvidia-*"
    dpkg-query -W -f='${Package}\n' | grep -E '^(libnvidia|nvidia-)' | sort -u | xargs -r apt-mark hold
}

hold_nvidia_packages() {
    log "Снятие hold для upgrade..."
    apt-mark showhold | grep -E '^(libnvidia|nvidia-)' | xargs -r apt-mark unhold || true
    install_nvidia_user_space
}

setup_hf_profile() {
    log "HF profile /etc/profile.d/llm-hf.sh"
    mkdir -p /srv/llm/models /srv/llm/hf/hub /srv/llm/hf/datasets
    cat >/etc/profile.d/llm-hf.sh <<'EOF'
# Hugging Face — данные на /srv/llm (mp0 shared storage)
export HF_HOME=/srv/llm/hf
export HF_HUB_CACHE=/srv/llm/hf/hub
export TRANSFORMERS_CACHE=/srv/llm/hf/hub
export HF_DATASETS_CACHE=/srv/llm/hf/datasets
EOF
    chmod 644 /etc/profile.d/llm-hf.sh
}

setup_base_packages() {
    log "Базовые пакеты"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        curl git python3 python3-venv python3-pip build-essential \
        openssh-server sudo zstd
}

setup_ssh_user() {
    if [ "$UPGRADE_ONLY" -eq 1 ]; then
        return 0
    fi
    log "SSH user $LLM_SSH_USER, port $LLM_SSH_PORT"
    if ! id "$LLM_SSH_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$LLM_SSH_USER"
        usermod -aG sudo "$LLM_SSH_USER"
    fi
    mkdir -p "/home/$LLM_SSH_USER/.ssh"
    chmod 700 "/home/$LLM_SSH_USER/.ssh"
    local keys_src="${LLM_AUTHORIZED_KEYS:-/root/.llm-bootstrap/authorized_keys}"
    if [ -f "$keys_src" ]; then
        cp "$keys_src" "/home/$LLM_SSH_USER/.ssh/authorized_keys"
    elif [ -f /root/.ssh/authorized_keys ] && [ -s /root/.ssh/authorized_keys ]; then
        cp /root/.ssh/authorized_keys "/home/$LLM_SSH_USER/.ssh/authorized_keys"
    else
        echo "WARN: authorized_keys не найден — добавьте ключ вручную в /home/$LLM_SSH_USER/.ssh/" >&2
        touch "/home/$LLM_SSH_USER/.ssh/authorized_keys"
    fi
    chmod 600 "/home/$LLM_SSH_USER/.ssh/authorized_keys"
    chown -R "$LLM_SSH_USER:$LLM_SSH_USER" "/home/$LLM_SSH_USER/.ssh"

    mkdir -p /etc/ssh/sshd_config.d
    cat >/etc/ssh/sshd_config.d/llm-gpu-base.conf <<EOF
Port ${LLM_SSH_PORT}
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
EOF
    systemctl enable ssh
    systemctl restart ssh
}

install_helper_scripts() {
    local dest=/usr/local/sbin
    mkdir -p "$dest"
    for script in upgrade-nvidia-user-space.sh sanitize-for-template.sh; do
        local src=""
        for d in /root/llm-gpu-scripts /opt/llm-gpu-scripts; do
            [ -f "$d/$script" ] && src="$d/$script" && break
        done
        [ -n "$src" ] && install -m 755 "$src" "$dest/${script%.sh}"
    done
}

if [ "$UPGRADE_ONLY" -eq 1 ]; then
    hold_nvidia_packages
    nvidia-smi 2>/dev/null | head -5 || true
    exit 0
fi

setup_base_packages
install_nvidia_user_space
setup_hf_profile
setup_ssh_user
install_helper_scripts

log "Bootstrap завершён. Проверки:"
ls /srv/llm/models 2>/dev/null | head -5 || echo "(models/ пуст или mount не готов)"
if ! nvidia-smi >/dev/null 2>&1; then
    echo "FAIL: nvidia-smi не работает после bootstrap." >&2
    exit 1
fi
nvidia-smi 2>/dev/null | head -4 || true
