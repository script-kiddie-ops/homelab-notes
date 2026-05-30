#!/usr/bin/env bash
# Обновление NVIDIA user-space в CT до версии, совместимой с драйвером хоста.
# Запуск внутри CT: upgrade-nvidia-user-space.sh
# Или: pct exec <VMID> -- upgrade-nvidia-user-space.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP="${SCRIPT_DIR}/bootstrap-llm-gpu-base.sh"
[ -f "$BOOTSTRAP" ] || BOOTSTRAP="/usr/local/sbin/bootstrap-llm-gpu-base"
[ -f "$BOOTSTRAP" ] || BOOTSTRAP="/root/bootstrap-llm-gpu-base.sh"

if [ -f "$BOOTSTRAP" ]; then
    exec bash "$BOOTSTRAP" --upgrade-only
fi

echo "bootstrap-llm-gpu-base.sh не найден — минимальный upgrade" >&2
apt-mark showhold | grep -E '^(libnvidia|nvidia-)' | xargs -r apt-mark unhold || true
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -o APT::Install-Recommends=false \
    libnvidia-ml1 libcuda1 nvidia-driver-cuda
dpkg-query -W -f='${Package}\n' | grep -E '^(libnvidia|nvidia-)' | sort -u | xargs -r apt-mark hold
nvidia-smi 2>/dev/null | head -5 || true
