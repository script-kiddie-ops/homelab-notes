# LLM-GPU base template (CT 900)

Базовый Proxmox CT template **`llm-gpu-base`** (VMID **900**) для контейнеров с локальным LLM-инференсом: Ubuntu 24.04, GPU passthrough, shared storage `/srv/llm`, NVIDIA user-space — **без** движка (vLLM, Ollama и т.д.).

Связанные материалы: [instruction.md](instruction.md) §11.2a–11.5, [02 — vLLM в LXC](02-vllm-lxc-deploy.md).

## Схема VMID

| VMID | Роль |
|------|------|
| **900** | Template `llm-gpu-base` (не запускается) |
| **101** | Legacy vLLM (`guests-vllm-ct`) — **не** из template |
| **102+** | Clone из 900 + engine-specific слой |

## Шпаргалка

| Задача | Действие |
|--------|----------|
| Создать template 900 | `bash scripts/pve/create-llm-gpu-template.sh` (root на PVE) |
| **Пересобрать 900 с нуля** | `bash scripts/pve/recreate-llm-gpu-template.sh` или `RUN_AS_ROOT.sh recreate` |
| Довести частичный 900 → template | `bash scripts/pve/fix-template-900.sh` (если не хотите destroy) |
| Новый LLM-CT | `bash scripts/pve/clone-llm-gpu-ct.sh <vmid> <hostname> <engine>` |
| Список clone от 900 | `bash scripts/pve/list-llm-gpu-clones.sh` |
| Продублировать `.conf` из эталона | [03a — propagate](03a-propagate-conf-from-template.md) |
| Обновить драйвер (хост → template → CT) | [03b — driver chain](03b-upgrade-nvidia-driver-chain.md) |
| Первый Ollama-CT (102) | `bash scripts/pve/deploy-llm-ct.sh --engine ollama` или `RUN_AS_ROOT.sh ollama` |
| Deploy clone (runbook) | [03c — deploy clone](03c-deploy-llm-gpu-clone.md) |
| **Эксплуатация Ollama** | [05 — operations](05-ollama-operations.md) |
| **Контекст / thinking Ollama** | [06 — inference settings](06-ollama-inference-settings.md) |
| Урезать RAM всем LLM-CT | `for id in $(list-llm-gpu-clones.sh); do pct set $id -memory 32768; done` |

## Что в template (rootfs)

- Ubuntu 24.04 privileged, NVIDIA user-space из CUDA repo `debian13` (§11.5a)
- `apt-mark hold` на `libnvidia-*` / `nvidia-*`
- `/etc/profile.d/llm-hf.sh` — `HF_HOME=/srv/llm/hf`, …
- Пакеты: `curl`, `git`, `python3`, `python3-venv`, `build-essential`, `openssh-server`
- Пользователь **`guests`**, SSH порт **1234**, ключи с хоста PVE
- **Нет:** vLLM, Ollama, `/etc/vllm/`

## Что в `.conf` (наследуется clone)

Эталон: [`scripts/pve/llm-gpu-base.conf.fragment`](scripts/pve/llm-gpu-base.conf.fragment)

- `mp0: /mnt/llm-shared,mp=/srv/llm`
- `hookscript: local:snippets/gpu-mutex.sh`
- `features: nesting=1`
- `lxc.mount.entry` / `lxc.cgroup2.devices.allow` для `/dev/nvidia*`

При clone задаются **уникально:** `net0`, `hostname`, `rootfs` subvol.

## Учёт clone

Proxmox **не хранит** ссылку «родитель = 900» для full clone. Реестр:

- Git: `scripts/pve/llm-gpu-clones.registry`
- На хосте: `/etc/llm-gpu/clones.registry` (ведёт `clone-llm-gpu-ct.sh`)
- Tag Proxmox: `llm-gpu-base`

## Создание template (один раз)

**Предусловия:** `bash scripts/pve/host-prep-check.sh`

**GPU mutex:** пока **101** (или другой member из `group.conf`) running, **900** не стартует. `create-llm-gpu-template.sh` сам останавливает GPU-гостей → bootstrap **900** → `pct template` → снова поднимает **101**.

**Важно (успешный путь):**

1. **`mp0`** нужен **только на время bootstrap** (модели в `/srv/llm/models`). Перед `pct template` строку **`mp0:`** убирают из `900.conf`; при **clone** её дописывает `clone-llm-gpu-ct.sh` из `llm-gpu-base.conf.fragment`.
2. **NVIDIA:** версия = **`nvidia-smi` на хосте** (`LLM_NVIDIA_DRIVER_VERSION`). Ставит `scripts/ct/bootstrap-llm-gpu-base.sh`: метапакет `nvidia-driver-cuda=<версия>`, временный **apt pin** (иначе repo тянет **610**), при смене ветки — **purge** старых `libnvidia-*`. Не ставить вручную три пакета без pin.

```bash
# на PVE под root:
cd /home/guests/llm-gpu-setup   # или proxmox-setup/scripts/pve
bash create-llm-gpu-template.sh
```

**Resume:** CT **900** уже есть, но нет template / сломан NVIDIA — `bash create-llm-gpu-template.sh` (resume) или **`bash fix-template-900.sh`**.

### Пересборка с нуля (проверка runbook)

Если template **900** уже есть и нужно убедиться, что инструкции и скрипты работают «с чистого листа»:

1. На PVE: `~/llm-gpu-setup/pve-deploy.env` — боевые `ZFS_POOL`, `LLM_PVE_HOME`, `LLM_SSH_*` (образец: `scripts/pve/pve-deploy.env.example`; реальные значения — `private/map`).
2. Скопировать актуальные скрипты с рабочей станции в `~/llm-gpu-setup/`.
3. Под **root**:

```bash
cd /home/guests/llm-gpu-setup   # на бою: /home/guests/llm-gpu-setup
bash RUN_AS_ROOT.sh prep          # опционально
RECREATE_YES=1 bash RUN_AS_ROOT.sh recreate
# или: bash scripts/pve/recreate-llm-gpu-template.sh
```

4. Ожидание: `host-prep-check` → `pct create 900` → bootstrap → `nvidia-smi` **595** = хост → sanitize → **убрать mp0** → `OK: template 900` → `pct start 101`.

5. Проверка: `pct list | grep 900` (template); clone-тест: `bash scripts/pve/clone-llm-gpu-ct.sh 899 test-clone test 900` и сразу `pct destroy 899` (опционально).

**Не трогаем:** CT **101** (legacy vLLM) — только временный stop на ~15–20 мин, vLLM недоступен.

### Быстрый старт на PVE (после копирования скриптов)

Скрипты развёрнуты на хосте в **`~/llm-gpu-setup/`** (user `guests`). Под **root**:

```bash
ssh -p 1234 guests@10.x.x.123
su -
cd /home/guests/llm-gpu-setup
bash RUN_AS_ROOT.sh all      # prep + template + pilot Ollama CT 102
# или по шагам:
bash RUN_AS_ROOT.sh prep
bash RUN_AS_ROOT.sh template
bash RUN_AS_ROOT.sh ollama
# пересоздать CT 102:
DESTROY_YES=1 bash scripts/pve/deploy-llm-ct.sh --engine ollama
```

## Clone нового CT

```bash
bash clone-llm-gpu-ct.sh 103 guests-sglang-ct sglang
# правка /etc/pve/lxc/103.conf — net0 (IP, gw)
pct start 103
# внутри CT — установка движка
```

## Shared storage — форматы моделей

| Путь | vLLM | Ollama |
|------|------|--------|
| `/srv/llm/models/` | HF weights | import / Modelfile |
| `/srv/llm/hf/` | HF cache | опционально |
| `/srv/llm/ollama/` | — | `OLLAMA_MODELS` |

На хосте один раз: `mkdir -p /mnt/llm-shared/ollama`

## Наследование настроек

Изменения RAM/cores в template **900 не применяются** к уже созданным CT автоматически. Новые clone получают конфиг **на момент** clone. Подробнее — в [03a](03a-propagate-conf-from-template.md).

## Скрипты

| Скрипт | Где запускать |
|--------|----------------|
| `host-prep-check.sh` | PVE root |
| `create-llm-gpu-template.sh` | PVE root |
| `clone-llm-gpu-ct.sh` | PVE root |
| `list-llm-gpu-clones.sh` | PVE root |
| `propagate-conf-from-template.sh` | PVE root |
| `deploy-llm-ct.sh` | PVE root — **один проход** clone + SSH + engine + verify |
| `install-ollama-engine.sh` | PVE root — только Ollama в running CT |
| `bootstrap-llm-gpu-base.sh` | внутри CT root |
| `sanitize-for-template.sh` | внутри CT root |
| `upgrade-nvidia-user-space.sh` | внутри CT root |
