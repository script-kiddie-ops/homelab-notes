# Настройки инференса: Ollama vs vLLM

Справочник по **контексту**, **параметрам генерации** и **режиму thinking** у **Qwen3** на домашнем стеке:

| CT | Движок | Модель | API |
|----|--------|--------|-----|
| **101** | vLLM | `Qwen3-8B-AWQ` | `http://10.x.x.101:8000` |
| **102** | Ollama | **`qwen3:8b`** | `http://10.x.x.102:11434` |

Эксплуатация Ollama: [05 — operations](05-ollama-operations.md). vLLM unit и флаги: [02 — vLLM](02-vllm-lxc-deploy.md), [instruction.md](instruction.md) §11.

---

## Где что настраивается (обзор)

| Параметр | vLLM (101) | Ollama (102) |
|----------|------------|--------------|
| Размер контекста | **systemd / CLI** (`--max-model-len`) | **env**, **Modelfile**, **запрос** (`num_ctx`) |
| VRAM / параллельность | `--gpu-memory-utilization`, `--max-num-seqs` | `num_ctx`, размер модели, env (`OLLAMA_*`) |
| Длина ответа | **запрос** (`max_tokens`) | **запрос** (`options.num_predict`) |
| Thinking (Qwen3) | **запрос** (`chat_template_kwargs`) | **запрос** (`think`), CLI (`/set nothink`) |

**Важно:** в vLLM контекст задаётся **глобально на процесс** — один KV-cache на весь сервер. В Ollama контекст можно менять **на сервере**, **на модели** и **в каждом запросе** (следите за VRAM).

Файлы **`Qwen3-8B-AWQ`** в `/srv/llm/models/` и blob **`qwen3:8b`** в `/srv/llm/ollama/` — **разные форматы и квантизации**. Одинаковый `8192` токенов контекста не гарантирует одинаковый расход VRAM и скорость.

---

## vLLM (CT 101) — эталон для сравнения

### Сервер (systemd)

Типичный `ExecStart` (см. [instruction.md](instruction.md)):

```ini
ExecStart=/opt/vllm-venv/bin/vllm serve ${MODEL_PATH} \
  --host ${LISTEN_HOST} --port ${LISTEN_PORT} \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --max-num-seqs 5
```

| Флаг | Смысл |
|------|--------|
| `--max-model-len 8192` | максимальная длина контекста (prompt + completion) |
| `--gpu-memory-utilization 0.90` | доля VRAM под KV и батчи |
| `--max-num-seqs 5` | параллельные последовательности |

При OOM первым уменьшают **`--max-model-len`**, затем `max-num-seqs` и `gpu-memory-utilization`.

### Запрос (OpenAI-compatible API)

```bash
curl -s http://10.x.x.101:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "Qwen3-8B-AWQ",
    "messages": [{"role": "user", "content": "ping"}],
    "max_tokens": 512
  }'
```

`max_tokens` — только **длина ответа**, не размер контекста.

### Qwen3 thinking в vLLM

По умолчанию модель может генерировать блок рассуждений в chat template (``-подобные маркеры) **перед** финальным текстом.

**Отключение в запросе** (non-thinking — прямой ответ, без видимого блока thinking):

```json
{
  "model": "Qwen3-8B-AWQ",
  "messages": [{"role": "user", "content": "ping"}],
  "max_tokens": 512,
  "chat_template_kwargs": {
    "enable_thinking": false
  }
}
```

Через OpenAI Python-клиент:

```python
client.chat.completions.create(
    model="Qwen3-8B-AWQ",
    messages=[{"role": "user", "content": "ping"}],
    max_tokens=512,
    extra_body={"chat_template_kwargs": {"enable_thinking": False}},
)
```

**Эффект:** в ответе API **нет** отдельного блока thinking; поведение смещается к более прямым ответам. Это не «выключение логики» — модель по-прежнему генерирует текст, но без явной цепочки рассуждений в выводе. На сложных задачах качество иногда чуть ниже, чем в thinking-режиме.

Для пайплайнов (editor, роутер) non-thinking обычно лучше: меньше лишних токенов и мусора в `.md`.

---

## Ollama (CT 102) — три уровня настроек

### 1. Сервер: systemd override и env

Файл (не править unit из `install.sh`):

```ini
# /etc/systemd/system/ollama.service.d/override.conf
[Service]
Environment="OLLAMA_MODELS=/srv/llm/ollama"
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_CONTEXT_LENGTH=8192"
```

После правки:

```bash
systemctl daemon-reload && systemctl restart ollama
```

| Переменная | Смысл |
|------------|--------|
| `OLLAMA_CONTEXT_LENGTH` | дефолтный `num_ctx` для всех моделей |
| `OLLAMA_NUM_PARALLEL` | число параллельных запросов (увеличивает расход RAM/VRAM) |
| `OLLAMA_FLASH_ATTENTION=1` | flash attention — меньше VRAM на длинном контексте |
| `OLLAMA_KV_CACHE_TYPE=q8_0` | квантизация KV-cache (экономия VRAM) |

**RTX 3060 12 GB:** Ollama на GPU с VRAM &lt; 24 GB часто выбирает **4096** токенов контекста по умолчанию. Чтобы сопоставить с vLLM **`--max-model-len 8192`**, задайте **`OLLAMA_CONTEXT_LENGTH=8192`** или `num_ctx` в Modelfile/запросе и проверьте VRAM (`ollama ps`, `nvidia-smi`).

Прямого аналога **`--gpu-memory-utilization`** в Ollama нет — VRAM определяется размером модели, `num_ctx`, параллельностью и env выше.

### 2. Модель: Modelfile (постоянно для образа)

```dockerfile
FROM qwen3:8b
PARAMETER num_ctx 8192
PARAMETER temperature 0.7
```

```bash
ollama create qwen3-8b-8k -f Modelfile
# в API: "model": "qwen3-8b-8k"
```

Аналог «зафиксировали в unit, а не в каждом curl».

Интерактивно в `ollama run`:

```text
/set parameter num_ctx 8192
```

### 3. Запрос: `/api/chat` и `/api/generate`

**Chat API** — полный пример «как vLLM 8K + без thinking»:

```bash
curl -s http://10.x.x.102:11434/api/chat -d '{
  "model": "qwen3:8b",
  "messages": [{"role": "user", "content": "ping"}],
  "stream": false,
  "think": false,
  "options": {
    "num_ctx": 8192,
    "num_predict": 512,
    "temperature": 0.7
  }
}'
```

**Generate API:**

```bash
curl -s http://10.x.x.102:11434/api/generate -d '{
  "model": "qwen3:8b",
  "prompt": "ping",
  "stream": false,
  "think": false,
  "options": {
    "num_ctx": 8192,
    "num_predict": 64
  }
}'
```

#### Соответствие параметров vLLM ↔ Ollama

| Ollama | vLLM / API | Примечание |
|--------|------------|------------|
| `options.num_ctx` | `--max-model-len` | размер контекста (prompt + место под ответ) |
| `options.num_predict` | `max_tokens` | макс. токенов в **ответе** |
| `options.temperature`, `top_p`, … | те же | сэмплинг |
| `think: false` | `chat_template_kwargs.enable_thinking: false` | только Qwen3 и совместимые thinking-модели |

Другие полезные `options`: `top_k`, `repeat_penalty`, `stop`, `seed` — см. [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md).

---

## Qwen3 thinking в Ollama

При первом smoke-тесте **`qwen3:8b`** ответ `/api/generate` может содержать отдельное поле **`thinking`** — модель рассуждала и отдавала цепочку в API.

| Способ | Команда / поле |
|--------|----------------|
| API chat / generate | **`"think": false`** |
| CLI | `ollama run qwen3:8b --think=false` |
| Интерактив | `/set nothink` |
| Явно включить | `"think": true` или `/set think` |

**Ответ `/api/chat`:**

- `message.content` — финальный текст для пользователя;
- при `think: true` дополнительно `message.thinking` — блок рассуждений;
- при `think: false` поле thinking пустое или отсутствует.

**Смысл** тот же, что у vLLM `enable_thinking: false`: в выдаче нет блока thinking, ответ короче и чище для downstream-агентов.

---

## Практическая шпаргалка (3060, Qwen3-8B)

### Цель: поведение близко к vLLM `8192` + non-thinking

1. **Сервер:** добавить `OLLAMA_CONTEXT_LENGTH=8192` в override (или Modelfile с `num_ctx 8192`).
2. **Запросы:** `"think": false`, `"options": {"num_predict": …}`.
3. **Проверка:**

```bash
ollama ps                    # колонка CONTEXT, VRAM
nvidia-smi                   # Memory-Usage под нагрузкой
curl -s http://10.x.x.102:11434/api/chat -d '...' | jq .
```

### Когда что выбирать

| Сценарий | Контекст | Thinking |
|----------|----------|----------|
| Обычный чат / editor / роутер | `8192` (или меньше при нехватке VRAM) | **`false`** |
| Сложные задачи / research | `8192` | **`true`** (больше токенов, блок thinking в контексте) |
| Экономия VRAM | `4096` (дефолт Ollama на 3060) | по задаче |

### GPU mutex

Одна **RTX 3060** — только один GPU-CT running. Перед сравнением vLLM ↔ Ollama переключайте CT (см. [05 — operations](05-ollama-operations.md)).

---

## Связанные материалы

| Документ | Тема |
|----------|------|
| [05 — Ollama operations](05-ollama-operations.md) | systemd, pull, API, mutex |
| [02 — vLLM](02-vllm-lxc-deploy.md) | deploy CT 101, флаги serve |
| [instruction.md](instruction.md) | полная инструкция, unit vLLM |
| [04 — Ollama CT 102](04-ollama-ct-from-template.md) | дневник первого deploy |
