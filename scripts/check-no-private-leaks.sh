#!/usr/bin/env bash
# Обёртка для pre-commit: делегирует в private/ (локально, не в git).
#
# Публичный clone / GitHub Actions без каталога private/ — проверка пропускается (exit 0).
# Паттерны боевых значений только в private/leak-patterns.conf — не коммитить.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE="$ROOT/private/check-no-private-leaks.sh"

if [ ! -f "$PRIVATE" ]; then
    echo "check-no-private-leaks: skip (нет private/ — локальная проверка на машине разработчика)"
    exit 0
fi

exec bash "$PRIVATE" "$@"
