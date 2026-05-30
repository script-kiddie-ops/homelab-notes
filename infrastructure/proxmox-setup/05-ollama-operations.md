# Эксплуатация Ollama (CT 102)

Runbook после [развёртывания CT из template 900](03c-deploy-llm-gpu-clone.md). Дневник первого deploy: [04 — Ollama CT 102](04-ollama-ct-from-template.md).

**CT:** `guests-ollama-ct` (VMID **102**), API **`http://10.x.x.102:11434`**, SSH **`ssh guests-102`**.

---

## Модели: vLLM vs Ollama

| Путь | Формат | Движок |
|------|--------|--------|
| `/srv/llm/models/` | Hugging Face (AWQ, safetensors) | **vLLM** (CT 101) |
| `/srv/llm/ollama/` | Ollama blobs | **Ollama** (CT 102) |

Файлы **Qwen3-8B-AWQ** в `models/` **нельзя** указать в Ollama — нужен **`ollama pull`**.

| vLLM (101) | Ollama (102) | VRAM (~3060) |
|------------|--------------|--------------|
| `Qwen3-8B-AWQ` | **`qwen3:8b`** | ~5–5.5 GiB |

Проверено: `qwen3:8b` ~5.2 GB на диске, ~5533 MiB VRAM под нагрузкой, API из LAN отвечает.

---

## GPU mutex: vLLM ↔ Ollama

Одна **RTX 3060** — только **один** GPU-CT **running**.

**Ollama (102):**

```bash
# PVE root
pct stop 101
pct start 102
curl -s http://10.x.x.102:11434/
```

**vLLM (101):**

```bash
pct stop 102
pct start 101
curl -s http://10.x.x.101:8000/v1/models | head
```

Список VMID в mutex: `/etc/gpu-mutex/group.conf` на PVE.

---

## Сервис Ollama (systemd)

Внутри CT 102 под **root** (`su -` или `pct exec 102 -- …`):

| Действие | Команда |
|----------|---------|
| Статус | `systemctl status ollama` |
| Запуск | `systemctl start ollama` |
| Остановка | `systemctl stop ollama` |
| Перезапуск | `systemctl restart ollama` |
| Логи | `journalctl -u ollama -n 50 --no-pager` |

Override (не править unit из install.sh):

```ini
# /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_MODELS=/srv/llm/ollama"
Environment="OLLAMA_HOST=0.0.0.0:11434"
```

После правки: `systemctl daemon-reload && systemctl restart ollama`.

Проверка:

```bash
ss -tlnp | grep 11434    # 0.0.0.0:11434
curl -s http://127.0.0.1:11434/
```

С **ноутбука:** `curl http://10.x.x.102:11434/` → `Ollama is running`.

---

## Установка и управление моделями

Команды на CT 102 (пользователь `guests` в группе `ollama` — достаточно обычного SSH):

```bash
ssh guests-102

# основная «средняя» (аналог Qwen3-8B-AWQ в vLLM)
ollama pull qwen3:8b

ollama list
ollama show qwen3:8b
ollama rm qwen3:8b          # удалить blob (освободить место на /srv/llm/ollama)
```

Другие размеры (при необходимости):

```bash
ollama pull qwen3:0.6b     # аналог MODEL_PATH_TINY
ollama pull qwen3:1.7b     # аналог MODEL_PATH_SMALL
```

Blobs на shared ZFS — с хоста PVE: `ls /mnt/llm-shared/ollama/`.

**Долгий pull:** лучше `tmux` / `screen`, чтобы обрыв SSH не прервал загрузку.

---

## Inference: тест и API

**Контекст 8K, thinking, сравнение с vLLM:** [06 — inference settings](06-ollama-inference-settings.md).

**Интерактив:**

```bash
ollama run qwen3:8b 'ping'
```

**Generate API (LAN):**

```bash
curl -s http://10.x.x.102:11434/api/generate -d '{
  "model": "qwen3:8b",
  "prompt": "ping",
  "stream": false
}'
```

**Chat API:**

```bash
curl -s http://10.x.x.102:11434/api/chat -d '{
  "model": "qwen3:8b",
  "messages": [{"role": "user", "content": "ping"}],
  "stream": false
}'
```

**GPU под нагрузкой:**

```bash
nvidia-smi
# ожидание: ~5–6 GiB VRAM, высокий GPU-Util
```

В LXC строка **Processes** в `nvidia-smi` иногда пустая — ориентируйтесь на **Memory-Usage**.

---

## SSH, пароли, root

- Вход: **`ssh guests-102`** (ключ с ноутбука).
- Пароли задаются **с PVE**: `pct exec 102 -- passwd guests` / `passwd root`.
- Root в CT без пароля по умолчанию — удобнее **`pct exec 102 -- bash`** с хоста PVE.

---

## Пересоздание CT 102 (runbook)

```bash
# PVE root, ~/llm-gpu-setup
DESTROY_YES=1 bash scripts/pve/deploy-llm-ct.sh --engine ollama
# затем снова:
ssh guests-102
ollama pull qwen3:8b
```

Blobs в `/srv/llm/ollama/` **сохраняются** на shared ZFS, если каталог не очищали вручную — повторный `pull` может быть быстрее.

---

## Шпаргалка

| Задача | Где / команда |
|--------|----------------|
| Deploy CT + Ollama | `bash scripts/pve/deploy-llm-ct.sh --engine ollama` |
| Переключить на Ollama | `pct stop 101 && pct start 102` |
| Скачать модель | `ollama pull qwen3:8b` |
| Проверка API | `curl http://10.x.x.102:11434/` |
| Restart сервиса | `systemctl restart ollama` |
| Список моделей | `ollama list` |

Связанные материалы: [03c — deploy](03c-deploy-llm-gpu-clone.md), [04 — дневник](04-ollama-ct-from-template.md), [06 — inference settings](06-ollama-inference-settings.md), vLLM-модели — [02 — vLLM](02-vllm-lxc-deploy.md) §12.2a.
