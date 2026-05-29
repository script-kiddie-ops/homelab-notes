# Первичные данные по запускам

Пока без бенчмаркинга инструментами, простая проверка работоспособности В LXT-контейнере:
загружаю модель, делаю единственный запрос к API со внешней машины
("как собрать электрогенератор самому"), смотрю логи.

Настройки vLLM: `--max-model-len 8192 --gpu-memory-utilization 0.90 --max-num-seqs 5`

`Qwen3-8B-AWQ`:

- nvidia-smi: 9727MiB /  12288MiB
- логи загрузки модели (journalctl -u vllm.service -f):
  - Model loading took 5.71 GiB memory and 13.215767 seconds
  - Available KV cache memory: 3.47 GiB
- логи отработки запроса: MAX(Avg generation throughput): ~57 tokens/s 

`Qwen3-1.7B`:

- nvidia-smi: 10449MiB /  12288MiB
- логи загрузки модели (journalctl -u vllm.service -f):
  - Model loading took 3.22 GiB memory and 7.291265 seconds
  - Available KV cache memory: 6.54 GiB
- логи отработки запроса: MAX(Avg generation throughput): ~82 tokens/s

`Qwen2.5-7B-Instruct-AWQ`:

- nvidia-smi: 9987MiB /  12288MiB
- логи загрузки модели (journalctl -u vllm.service -f):
  - Model loading took 5.2 GiB memory and 11.712123 seconds
  - Available KV cache memory: 4.12 GiB
- логи отработки запроса: MAX(Avg generation throughput): ~50 tokens/s

`Qwen3-0.6B`:

- nvidia-smi: 10687MiB /  12288MiB
- логи загрузки модели (journalctl -u vllm.service -f):
  - Model loading took 1.12 GiB memory and 2.748736 seconds
  - Available KV cache memory: 8.93 GiB
- логи отработки запроса: MAX(Avg generation throughput): ~54 tokens/s

**Анализ от Курсора**:

`nvidia-smi` (~9.7–10.7 GiB) при всех моделях почти одинаков по смыслу: vLLM с `--gpu-memory-utilization 0.90` резервирует ~90% карты под пул (веса + KV + compile/cudagraph). Меньшая модель не освобождает лишнее в `nvidia-smi` — она получает больший KV-пул.

Сравнивать модели логичнее по:

- `Model loading took X GiB` — веса на GPU
- `Available KV cache memory` — бюджет под контекст/параллельные запросы

|Модель|Веса (лог)|KV (лог)|nvidia-smi|Скорость (пик gen)|
|---|---|---|---|---|
|Qwen3-0.6B|1.12 GiB|8.93 GiB|10687 MiB|~54 tok/s|
|Qwen3-1.7B|3.22 GiB|6.54 GiB|10449 MiB|~82 tok/s|
|Qwen2.5-7B-AWQ|5.20 GiB|4.12 GiB|9987 MiB|~50 tok/s|
|Qwen3-8B-AWQ|5.71 GiB|3.47 GiB|9727 MiB|~57 tok/s|

При одном запросе KV usage в логах низкий (0.7–6.8%) — запас большой; узкое место при нескольких длинных сессиях — именно KV, не веса.
