# результаты по `vllm bench serve`

`Qwen3-8B-AWQ`

`--max-model-len 8192 --gpu-memory-utilization 0.90 --max-num-seqs 5`

## Запускаем `smoke` и `load`

разница такая:

```bash
...
COMMON=(
    bench serve
    --backend openai-chat
    --host "$HOST"
    --port "$PORT"
    --endpoint /v1/chat/completions
    --model "$MODEL"
    --save-result
    --result-dir "$RESULT_DIR"
)

case "$PROFILE" in
    smoke)
        "$VLLM_BIN" "${COMMON[@]}" \
            --dataset-name random \
            --random-input-len 512 \
            --random-output-len 128 \
            --num-prompts 20 \
            --max-concurrency 1
        ;;
    load)
        "$VLLM_BIN" "${COMMON[@]}" \
            --dataset-name random \
            --random-input-len 1024 \
            --random-output-len 256 \
            --num-prompts 50 \
            --max-concurrency 5 \
            --request-rate 2 \
            --save-detailed
        ;;
    *)
        echo "Usage: $0 smoke|load" >&2
        exit 1
        ;;
esac
...
```

## 1. root@guests-vllm-ct:~# ./bench-vllm-serve.sh smoke

```
Burstiness factor: 1.0 (Poisson process)
Maximum request concurrency: 1

============ Serving Benchmark Result ============
Successful requests:                     20
Failed requests:                         0
Maximum request concurrency:             1
Benchmark duration (s):                  50.19
Total input tokens:                      10400
Total generated tokens:                  2560
Request throughput (req/s):              0.40
Output token throughput (tok/s):         51.01
Peak output token throughput (tok/s):    59.00
Peak concurrent requests:                2.00
Total token throughput (tok/s):          258.22
---------------Time to First Token----------------
Mean TTFT (ms):                          320.70
Median TTFT (ms):                        317.38
P99 TTFT (ms):                           377.87
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          17.23
Median TPOT (ms):                        17.24
P99 TPOT (ms):                           17.27
---------------Inter-token Latency----------------
Mean ITL (ms):                           17.10
Median ITL (ms):                         17.23
P99 ITL (ms):                            17.65
==================================================
Results dir: /srv/llm/benchmarks/20260518-2143-qwen3-8b-awq-smoke
```

## 2. root@guests-vllm-ct:~# ./bench-vllm-serve.sh load

```
Burstiness factor: 1.0 (Poisson process)
Maximum request concurrency: 5

============ Serving Benchmark Result ============
Successful requests:                     50
Failed requests:                         0
Maximum request concurrency:             5
Request rate configured (RPS):           2.00
Benchmark duration (s):                  80.78
Total input tokens:                      51600
Total generated tokens:                  12800
Request throughput (req/s):              0.62
Output token throughput (tok/s):         158.45
Peak output token throughput (tok/s):    235.00
Peak concurrent requests:                8.00
Total token throughput (tok/s):          797.20
---------------Time to First Token----------------
Mean TTFT (ms):                          634.29
Median TTFT (ms):                        660.92
P99 TTFT (ms):                           1265.15
-----Time per Output Token (excl. 1st token)------
Mean TPOT (ms):                          28.58
Median TPOT (ms):                        28.73
P99 TPOT (ms):                           31.18
---------------Inter-token Latency----------------
Mean ITL (ms):                           28.47
Median ITL (ms):                         21.69
P99 ITL (ms):                            328.33
==================================================
Results dir: /srv/llm/benchmarks/20260518-2146-qwen3-8b-awq-load
```
