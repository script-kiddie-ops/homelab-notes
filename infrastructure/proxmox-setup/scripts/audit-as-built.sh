#!/usr/bin/env bash
# Read-only snapshot of PVE host + LLM CT(s). Run on laptop:
#   ./scripts/audit-as-built.sh
#   ./scripts/audit-as-built.sh --clones   # also audit VMIDs from clones.registry on host
#
# SSH hosts (first match): guests-pve, guests-101 (см. ssh_notes.md)

set -euo pipefail

AUDIT_CLONES=0
[ "${1:-}" = "--clones" ] && AUDIT_CLONES=1

ssh_host() {
  local host
  for host in guests-pve; do
    if ssh -F "${HOME}/.ssh/config" -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null; then
      echo "$host"
      return 0
    fi
  done
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -p 1234 guests@10.x.x.123 true 2>/dev/null; then
    echo "direct:guests@10.x.x.123:1234"
    return 0
  fi
  return 1
}

ssh_ct101() {
  for host in guests-101; do
    ssh -F "${HOME}/.ssh/config" -o BatchMode=yes -o ConnectTimeout=5 "$host" true 2>/dev/null && echo "$host" && return 0
  done
  ssh -o BatchMode=yes -o ConnectTimeout=5 -p 1234 guests@10.x.x.101 true 2>/dev/null && echo "direct:guests@10.x.x.101:1234" && return 0
  return 1
}

run_ssh() {
  local target="$1"
  shift
  case "$target" in
    direct:*)
      local rest="${target#direct:}"
      local user="${rest%%@*}"
      local hostport="${rest#*@}"
      local host="${hostport%%:*}"
      local port="${hostport##*:}"
      ssh -o BatchMode=yes -p "$port" "$user@$host" "$@"
      ;;
    *)
      ssh -F "${HOME}/.ssh/config" -o BatchMode=yes "$target" "$@"
      ;;
  esac
}

PVE_HOST="$(ssh_host)" || { echo "PVE host unreachable" >&2; exit 1; }

run_host() {
  run_ssh "$PVE_HOST" 'bash -s' <<'EOF'
echo "=== PVE HOST ==="
hostname; date -Is
ip -4 -br addr | grep -v '^lo'
pveversion 2>/dev/null || true
zpool list 2>/dev/null || true
zfs list 2>/dev/null | grep -E 'llm|netac' | head -15 || true
nvidia-smi 2>/dev/null | head -12 || echo "(no nvidia-smi)"
echo "--- template 900 ---"
pct list 2>/dev/null | grep -E '900|101|102' || true
[ -f /etc/llm-gpu/clones.registry ] && echo "--- clones.registry ---" && grep -v '^#' /etc/llm-gpu/clones.registry || true
EOF
}

run_ct_by_ip() {
  local ip="$1"
  local label="$2"
  ssh -o BatchMode=yes -o ConnectTimeout=5 -p 1234 "guests@${ip}" 'bash -s' <<EOF
echo "=== ${label} ==="
hostname; date -Is
ip -4 -br addr | grep eth0 || true
nvidia-smi 2>/dev/null | head -8 || echo "(no nvidia-smi)"
systemctl is-active vllm 2>/dev/null || systemctl is-active ollama 2>/dev/null || true
df -h / /srv/llm 2>/dev/null || true
ls /srv/llm/models 2>/dev/null | head -5 || true
EOF
}

run_ct101() {
  local ct
  if ct="$(ssh_ct101)"; then
    run_ssh "$ct" 'bash -s' <<'EOF'
echo "=== CT 101 ==="
hostname; date -Is
nvidia-smi 2>/dev/null | head -8 || true
systemctl is-active vllm 2>/dev/null || true
/opt/vllm-venv/bin/pip show vllm 2>/dev/null | grep -E '^Version:' || true
ls /srv/llm/models 2>/dev/null | head -5 || true
EOF
  else
    run_ct_by_ip 10.x.x.101 "CT 101" 2>/dev/null || echo "(CT 101 unreachable)"
  fi
}

run_host
echo
run_ct101

if [ "$AUDIT_CLONES" -eq 1 ]; then
  echo
  echo "=== Clone CT audit ==="
  mapfile -t VMIDS < <(run_ssh "$PVE_HOST" 'grep -v "^#" /etc/llm-gpu/clones.registry 2>/dev/null | awk "{print \$1}" | grep -E "^[0-9]+$"' || true)
  for vmid in "${VMIDS[@]}"; do
    ip="$(run_ssh "$PVE_HOST" "grep -E \"^${vmid}[[:space:]]\" /etc/pve/lxc/${vmid}.conf 2>/dev/null | grep -oE 'ip=[^,]+' | cut -d= -f2 | cut -d/ -f1" 2>/dev/null || true)"
    [ -n "$ip" ] && run_ct_by_ip "$ip" "CT $vmid" || echo "(CT $vmid: no IP or unreachable)"
    echo
  done
fi
