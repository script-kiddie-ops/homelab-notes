# Runbook: обновление NVIDIA — хост → template → контейнеры

Цепочка после `apt upgrade` драйвера на Proxmox или смены major у `/dev/nvidia*`.

Зафиксированная версия на момент создания template: **595.71.05** (CUDA repo `debian13`).

См.: [instruction.md §11.5a](instruction.md), [03 — template](03-llm-gpu-base-template.md).

## Схема

```
1. PVE Host     — kernel driver (nvidia-smi на хосте)
2. Template 900 — user-space libs (пересборка template)
3. Clone CT     — upgrade-nvidia-user-space.sh в каждом VMID из registry
3b. CT 101      — legacy, тот же скрипт вручную
```

## Шаг 0. Чеклист до обновления

- [ ] `nvidia-smi | head -3` на хосте и в CT 101 / clone — записать версии
- [ ] Остановить LLM-сервисы: `systemctl stop vllm` / `ollama` внутри CT
- [ ] Остановить GPU-CT (или по одному при mutex)
- [ ] Backup: `/etc/pve/lxc/*.conf`, `/etc/llm-gpu/clones.registry`

## Шаг 1. Хост PVE

По [instruction.md §10](instruction.md): обновить драйвер, reboot, проверить:

```bash
nvidia-smi                    # Driver Version
ls -l /dev/nvidia*            # majors для conf.fragment
```

Если **major** изменился — обновить `scripts/pve/llm-gpu-base.conf.fragment`, затем [03a propagate](03a-propagate-conf-from-template.md) на все LLM-CT + вручную 101.

## Шаг 2. Пересборка template 900

Template нельзя патчить in-place.

```bash
# временный build CT
pct clone 900 899 --full 1 --hostname llm-gpu-base-build
pct start 899

# скопировать скрипты (если ещё не в образе)
pct push 899 /path/to/upgrade-nvidia-user-space.sh /root/upgrade-nvidia-user-space.sh
pct exec 899 -- bash /root/upgrade-nvidia-user-space.sh
# или: pct exec 899 -- bash /root/llm-gpu-scripts/bootstrap-llm-gpu-base.sh --upgrade-only

pct exec 899 -- nvidia-smi
pct exec 899 -- bash /root/llm-gpu-scripts/sanitize-for-template.sh
pct stop 899

pct destroy 900          # старый template
pct template 899         # новый template (VMID 899; при необходимости переименовать в 900 — см. документацию PVE)
```

> **VMID 900:** после `pct destroy 900` можно создать новый template с VMID 900 через `pct clone 899 900 --full 1` + `pct template 900` + destroy 899 — зафиксируйте рабочий порядок для вашей версии PVE.

## Шаг 3. Каждый clone из registry

```bash
REGISTRY=/etc/llm-gpu/clones.registry
for id in $(bash scripts/pve/list-llm-gpu-clones.sh); do
  echo "=== CT $id ==="
  pct stop "$id" || true
  pct start "$id"
  pct push "$id" /path/to/scripts/ct/upgrade-nvidia-user-space.sh /root/upgrade-nvidia-user-space.sh
  pct exec "$id" -- bash /root/upgrade-nvidia-user-space.sh
  pct exec "$id" -- nvidia-smi | head -3
  # systemctl restart ollama  # или vllm — по engine
  pct stop "$id"
done
```

## Шаг 3b. CT 101 (legacy)

```bash
pct push 101 /path/to/scripts/ct/upgrade-nvidia-user-space.sh /root/upgrade-nvidia-user-space.sh
pct exec 101 -- bash /root/upgrade-nvidia-user-space.sh
pct exec 101 -- systemctl restart vllm
```

## Шаг 4. Проверка

| Где | Команда | Ожидание |
|-----|---------|----------|
| Host | `nvidia-smi` | новая Driver Version |
| Template build CT | `nvidia-smi` | та же версия, без mismatch |
| Каждый clone | `nvidia-smi` | совпадение с хостом |
| CT 101 | `curl http://127.0.0.1:8000/v1/models` | API отвечает |

Опционально: `./scripts/audit-as-built.sh --clones` — обход registry.

## Что делает upgrade-nvidia-user-space.sh

Вызывает **`bootstrap-llm-gpu-base.sh --upgrade-only`** (тот же путь, что при сборке template):

1. `apt-mark unhold` → при смене major — **purge** старых NVIDIA-пакетов
2. **apt pin** на версию хоста → `nvidia-driver-cuda=<версия>` из CUDA repo `debian13`
3. `apt-mark hold` → `nvidia-smi`

Задайте **`LLM_NVIDIA_DRIVER_VERSION`** (с хоста). Вручную `apt install libnvidia-ml1 libcuda1 …` без pin — риск **610** и **Driver/library version mismatch**.
