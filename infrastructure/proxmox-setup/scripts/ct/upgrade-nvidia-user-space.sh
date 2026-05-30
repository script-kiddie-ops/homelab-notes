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

echo "bootstrap-llm-gpu-base.sh не найден — установите скрипт в /root/llm-gpu-scripts или /usr/local/sbin" >&2
exit 1
