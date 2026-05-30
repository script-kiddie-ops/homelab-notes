# Runbook: пропагация `.conf` из эталона во все LLM-GPU clone

Когда меняются общие настройки GPU, shared mount или mutex — их нужно **явно** перенести в уже работающие CT. Proxmox не синхронизирует template с clone автоматически.

**Источник правды:** [`scripts/pve/llm-gpu-base.conf.fragment`](scripts/pve/llm-gpu-base.conf.fragment) (в git), не «живой» template 900.

См. также: [03 — LLM-GPU base template](03-llm-gpu-base-template.md).

## Что propagate, что нет

| Поле | Propagate | Примечание |
|------|-----------|------------|
| `lxc.mount.entry` (GPU) | да | После смены драйвера — сверить major: `ls -l /dev/nvidia*` |
| `lxc.cgroup2.devices.allow` | да | |
| `mp0`, `hookscript`, `features` | да | |
| `memory`, `cores`, `swap` | опционально | Флаг `--include-resources`; по умолчанию **нет** |
| `net0`, `hostname`, `rootfs` | **нет** | Уникальны per-CT |
| CT **101** (legacy) | вручную | Не в registry; при необходимости скопировать GPU-блок из fragment |

## Список целевых CT

```bash
bash scripts/pve/list-llm-gpu-clones.sh
# или
grep -v '^#' /etc/llm-gpu/clones.registry | awk '{print $1}'
```

## Порядок действий

1. **Обновить эталон** — правки в `llm-gpu-base.conf.fragment`, commit в git.

2. **Dry-run** — посмотреть diff для каждого CT:
   ```bash
   bash scripts/pve/propagate-conf-from-template.sh --dry-run
   # или для конкретных VMID:
   bash scripts/pve/propagate-conf-from-template.sh --dry-run 102 103
   ```

3. **Применить:**
   ```bash
   bash scripts/pve/propagate-conf-from-template.sh 102 103
   ```
   Скрипт создаёт backup `NNN.conf.bak.<timestamp>`.

4. **Перезапуск** — по одному CT (GPU mutex):
   ```bash
   pct stop 102 && pct start 102
   ```

5. **Проверка внутри CT:**
   ```bash
   nvidia-smi
   ls /srv/llm/models
   systemctl status ollama   # или vllm
   ```

## Массовое изменение RAM (не через propagate)

Template не управляет ресурсами существующих CT:

```bash
for id in $(bash scripts/pve/list-llm-gpu-clones.sh); do
  pct set "$id" -memory 32768
done
```

## CT 101

Если менялись только GPU majors / mount entries — скопируйте соответствующие строки из fragment в `/etc/pve/lxc/101.conf` вручную или добавьте `101` в аргументы propagate (если conf существует и вы осознанно включаете legacy CT).
