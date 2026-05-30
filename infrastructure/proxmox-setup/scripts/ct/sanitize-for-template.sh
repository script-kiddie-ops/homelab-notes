#!/usr/bin/env bash
# Очистка CT перед pct template — убрать историю, кэши, временные файлы.
# Запуск внутри CT под root: bash sanitize-for-template.sh

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root внутри CT." >&2
    exit 1
fi

echo "==> sanitize for template"

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -f /root/.bash_history
history -c 2>/dev/null || true

find /var/log -type f -name '*.log' -exec truncate -s 0 {} \; 2>/dev/null || true
find /var/log -type f -name '*.gz' -delete 2>/dev/null || true
rm -f /var/log/wtmp /var/log/btmp /var/log/lastlog 2>/dev/null || true

rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
rm -rf /root/.cache 2>/dev/null || true

for u in /home/*; do
    [ -d "$u" ] || continue
    rm -f "$u/.bash_history" 2>/dev/null || true
done

echo "==> done"
