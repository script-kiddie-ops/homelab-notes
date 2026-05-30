# Proxmox VE: установка и vLLM в LXC

Раздел **[script-kiddie-ops](../../README.md)** → `infrastructure/proxmox-setup`.

Домашний узел: **ASRock B550M Steel Legend**, **Ryzen 3900**, **96 GiB RAM**, **RTX 3060 12 GB** + **RX 550 2 GB**. **Proxmox VE 9.1** на NVMe, гости и данные — **ZFS** `netacA` на SATA 4 TB.

## Доступ (актуально, май 2026)

| Куда | SSH | IP |
|------|-----|-----|
| Хост PVE (`host`) | `ssh guests-pve` | `10.x.x.123:1234`, user `guests` |
| CT vLLM, VMID **101** (`guests-vllm-ct`) | `ssh guests-101` | `10.x.x.101:1234`, user `guests` |
| API vLLM | — | `http://10.x.x.101:8000` |
| Web Proxmox | — | `https://10.x.x.123:8006` |

**VMID:** 900 = template `llm-gpu-base`; 101 = vLLM (legacy); 102+ = clone + engine (Ollama, …).

Раньше на **Ubuntu по Wi‑Fi** был **`10.x.x.225`** — в [статье 01](01-proxmox-home-deploy.md) это история, не текущий адрес хоста.

Повторный снимок состояния: [`scripts/audit-as-built.sh`](scripts/audit-as-built.sh).

## Содержание

| Файл | Назначение |
|------|------------|
| [01 — Proxmox дома](01-proxmox-home-deploy.md) | Дневник: установка PVE, сеть, ZFS, NVIDIA на хосте |
| [02 — vLLM в LXC](02-vllm-lxc-deploy.md) | Дневник: CT 101, GPU, vLLM, замеры |
| [03 — LLM-GPU base template](03-llm-gpu-base-template.md) | Template CT 900, clone, runbook'и |
| [03c — deploy clone](03c-deploy-llm-gpu-clone.md) | Один проход: новый CT, SSH, пароли, Ollama |
| [03a — propagate conf](03a-propagate-conf-from-template.md) | Тиражирование `.conf` на clone |
| [03b — NVIDIA driver chain](03b-upgrade-nvidia-driver-chain.md) | Хост → template → контейнеры |
| [04 — Ollama CT 102](04-ollama-ct-from-template.md) | Дневник: Ollama из template 900 |
| [05 — Ollama operations](05-ollama-operations.md) | Модели, systemd, API, mutex с vLLM |
| [06 — Ollama inference](06-ollama-inference-settings.md) | Контекст, `num_ctx`, thinking Qwen3, сравнение с vLLM |
| [instruction.md](instruction.md) | Пошаговая инструкция (фазы 0–12) |
| [vllm_serve_first_data.md](vllm_serve_first_data.md) | Первые замеры моделей на 3060 |
| [vllm_bench_serve.md](vllm_bench_serve.md) | Результаты `vllm bench serve` |
| [ssh_notes.md](ssh_notes.md) | Заметки по настройке SSH (порт 1234, `ssh.socket`, ключи) |
| [update-starlette-cve-2026-48710.md](update-starlette-cve-2026-48710.md) | Патч Starlette 1.0.1 (BadHost), проверки, пины venv |
| `scripts/pve/` | `gpu-mutex`, `deploy-llm-ct.sh`, `clone-llm-gpu-ct.sh`, template scripts, audit |
