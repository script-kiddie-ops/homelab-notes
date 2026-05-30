#!/usr/bin/env bash
# Запуск на PVE под root (su - или sudo bash):
#   cd ~/llm-gpu-setup && bash RUN_AS_ROOT.sh [all|prep|template|recreate|ollama|deploy]
#
# Скопировано с рабочей станции в ~/llm-gpu-setup/

set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PVE="$BASE/scripts/pve"

if [ -f "$BASE/pve-deploy.env" ]; then
    # shellcheck disable=SC1091
    set -a && source "$BASE/pve-deploy.env" && set +a
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Запустите от root: su - && bash $BASE/RUN_AS_ROOT.sh $*" >&2
    exit 1
fi

PHASE="${1:-all}"

run_prep() {
    bash "$PVE/host-prep-check.sh"
}

run_template() {
    bash "$PVE/create-llm-gpu-template.sh"
}

run_recreate() {
    bash "$PVE/recreate-llm-gpu-template.sh"
}

run_ollama() {
    bash "$PVE/deploy-llm-ct.sh" --engine ollama
}

run_deploy() {
    bash "$PVE/deploy-llm-ct.sh" "$@"
}

case "$PHASE" in
    prep) run_prep ;;
    template) run_template ;;
    recreate) run_recreate ;;
    ollama) run_ollama ;;
    deploy) shift; run_deploy "$@" ;;
    all)
        run_template
        run_ollama
        ;;
    *)
        echo "Usage: $0 [all|prep|template|recreate|ollama|deploy [--engine ollama|none ...]]" >&2
        exit 1
        ;;
esac

echo "=== Done: $PHASE ==="
