# Deploy LLM-GPU CT из template 900

Runbook: **новый контейнер** из template **`llm-gpu-base` (900)** — с движком (Ollama) или **без** (только GPU + shared storage + SSH). Один проход: [`deploy-llm-ct.sh`](scripts/pve/deploy-llm-ct.sh).

Связано: [03 — template](03-llm-gpu-base-template.md), [03a — propagate conf](03a-propagate-conf-from-template.md).

## Предусловия

- Template **900** существует (`pct list | grep 900`).
- На PVE: `~/llm-gpu-setup/pve-deploy.env` (образец [`pve-deploy.env.example`](scripts/pve/pve-deploy.env.example)).
- Скрипты скопированы на хост (rsync с рабочей станции или git clone).

```bash
ssh -p 1234 guests@10.x.x.123
su -
cd /home/guests/llm-gpu-setup
bash scripts/pve/host-prep-check.sh   # опционально
```

## Один проход: Ollama (CT 102)

Значения по умолчанию из `pve-deploy.env`: VMID **102**, `guests-ollama-ct`, `10.x.x.102/24`.

```bash
bash RUN_AS_ROOT.sh ollama
# то же:
bash scripts/pve/deploy-llm-ct.sh --engine ollama
```

**Пересоздать** CT с нуля (проверка runbook):

```bash
DESTROY_YES=1 bash scripts/pve/deploy-llm-ct.sh --engine ollama
```

Скрипт выполняет:

1. `pct clone 900 → VMID` (full), `mp0`, GPU, hookscript, registry, mutex group
2. `net0` (IP, gw)
3. stop других GPU-CT из `group.conf`, `pct start`
4. sync SSH-ключей с хоста PVE → CT
5. engine **ollama**: `zstd`, install.sh, `OLLAMA_MODELS=/srv/llm/ollama`, `OLLAMA_HOST=0.0.0.0`, `chown ollama:ollama`
6. verify: `nvidia-smi`, API `:11434` с LAN, mutex

## Clone без движка (103, SGLang, …)

```bash
bash scripts/pve/deploy-llm-ct.sh \
  --vmid 103 \
  --hostname guests-sglang-ct \
  --ip 10.x.x.103/24 \
  --gw 10.x.x.1 \
  --engine none
```

Дальше внутри CT — установка движка вручную или отдельным скриптом.

Минимальный путь (только clone, без deploy-llm-ct):

```bash
bash scripts/pve/clone-llm-gpu-ct.sh 103 guests-sglang-ct sglang
# правка net0 в /etc/pve/lxc/103.conf
pct start 103
```

## SSH-ключи в CT

Template кладёт ключи при bootstrap, но надёжнее **синхронизировать с хоста PVE** после clone (делает `deploy-llm-ct.sh`):

```bash
pct push 102 /home/guests/.ssh/authorized_keys /tmp/llm-authorized_keys
pct exec 102 -- bash -c '
  install -d -m 700 -o guests -g guests /home/guests/.ssh
  install -m 600 -o guests -g guests /tmp/llm-authorized_keys /home/guests/.ssh/authorized_keys
  rm -f /tmp/llm-authorized_keys
  systemctl restart ssh
'
```

На ноутбуке — `ssh-copy-id` **до** отключения паролей или alias в `~/.ssh/config` (см. [ssh_notes.md](ssh_notes.md)).

## Пароли `guests` и root (опционально)

В CT из template **пароли не заданы** — вход по ключу; `su -` / `sudo` без пароля не работают.

Задать **с хоста PVE** (интерактивно):

```bash
pct exec 102 -- passwd guests
pct exec 102 -- passwd root
```

Проверка:

```bash
ssh -p 1234 guests@10.x.x.102
sudo -i          # пароль guests
# или
su -               # пароль root
```

**Не коммитить** пароли в git. Для автоматизации — только на хосте, вне репозитория.

## GPU mutex

Только **один** CT из `/etc/gpu-mutex/group.conf` может быть **running** (одна RTX 3060).

| Действие | Команда |
|----------|---------|
| Ollama (102) | `pct stop 101 && pct start 102` |
| vLLM (101) | `pct stop 102 && pct start 101` |

`deploy-llm-ct.sh` сам останавливает peers перед стартом нового CT.

## Переменные `pve-deploy.env`

| Переменная | Назначение |
|------------|------------|
| `ZFS_POOL` | `netacA` |
| `LLM_PVE_HOME` | `/home/guests` — откуда брать `.ssh/authorized_keys` |
| `LLM_SSH_USER` / `LLM_SSH_PORT` | пользователь и порт SSH в CT |
| `OLLAMA_*` / `DEPLOY_*` | VMID, hostname, IP для `--engine ollama` |

## Скрипты

| Скрипт | Назначение |
|--------|------------|
| [`deploy-llm-ct.sh`](scripts/pve/deploy-llm-ct.sh) | **Один проход** clone + SSH + engine + verify |
| [`clone-llm-gpu-ct.sh`](scripts/pve/clone-llm-gpu-ct.sh) | Только clone + registry + mutex (без net/engine) |
| [`install-ollama-engine.sh`](scripts/pve/install-ollama-engine.sh) | Только Ollama внутри уже running CT |
| [`list-llm-gpu-clones.sh`](scripts/pve/list-llm-gpu-clones.sh) | Список clone из registry |
