# Обслуживание и диагностика железа homelab (PVE + LLM)

Runbook для домашнего узла из [README](README.md): ZFS, SMART, GPU, RAM, **ручной бэкап на USB**.

Узел: **ASRock B550M**, **Ryzen 3900**, **96 GiB RAM**, **RTX 3060 12 GB**, **RX 550**, **Proxmox VE 9.1**, ZFS **`netacA`** (SATA 4 TB), CT **101** (vLLM), template **900**, clone **102+** (Ollama и др.). SSH — [ssh_notes.md](ssh_notes.md), доступ — таблица в README.

---

## 1. Ритм обслуживания

| Когда | Что |
|-------|-----|
| **После reboot / сбоя ZFS** | `zpool status`, write-test, `pct start 101`, SMART (см. §3) |
| **Раз в месяц** | SMART диска 4 TB, `zpool list`, место на pool, `nvidia-smi`, `systemctl status vllm` |
| **Раз в квартал** | `zpool scrub netacA`, **бэкап на внешний USB** (§3.6), обновления PVE (осознанно), сверка драйвера NVIDIA хост ↔ CT, `memtest` при подозрении на RAM |
| **Перед WAN / пробросом портов** | Отдельный чеклист hardening (вне этого репозитория) |

Записывайте дату и краткий итог в конец этого файла (§10) или в отдельную заметку.

---

## 2. Быстрый health-check (5 минут)

С **ноутбука** (SSH — `guests-pve`, `guests-101`, см. README):

```bash
# хост PVE
ssh guests-pve 'hostname; uptime; zpool list netacA; zpool status netacA | head -15; nvidia-smi | head -8'

# CT vLLM
ssh guests-101 'systemctl is-active vllm; nvidia-smi | head -6; df -h / /srv/llm'
curl -sS -m 3 http://10.x.x.101:8000/v1/models | head
```

На **хосте под root** (если нужны pct/zfs без ограничений):

```bash
pct list
zfs list -r netacA | head -20
```

---

## 3. Диск ZFS `netacA` (Netac 4 TB SATA)

### 3.1. Статус pool

```bash
zpool status -v netacA
zpool list netacA
```

| Состояние | Действие |
|-----------|----------|
| **ONLINE**, errors 0 | Норма |
| **DEGRADED** / **FAULTED** | Не писать на pool; SMART + кабель SATA; см. §3.3 |
| **SUSPENDED** | Остановить CT на pool (`pct stop 101` …), **reboot** хоста; не ждать зависший `zpool export`. Скрипт: `~/llm-gpu-setup/scripts/pve/zfs-recover-pool.sh` |

### 3.2. Проверка записи

```bash
zfs create -o mountpoint=none netacA/.write-test && zfs destroy netacA/.write-test && echo OK
```

Если ошибка — не создавать новые CT на `netacA` до восстановления.

### 3.3. SMART (как читать вывод)

```bash
# by-id стабильнее /dev/sdX; серийник смотрите: ls -l /dev/disk/by-id/ata-*
DISK=/dev/disk/by-id/ata-<Vendor>_SSD_4TB_<serial>
smartctl -a "$DISK" | grep -iE 'health|error|realloc|CRC|Temperature'
```

| Строка / атрибут | Хорошо | Тревога |
|------------------|--------|---------|
| **SMART overall-health: PASSED** | Да | **FAILED** → §3.6 (USB), замена диска |
| **No Errors Logged** | Да | Есть записи в SMART Error Log |
| **Reallocated_Sector_Ct** RAW | **0** (стабильно) | Рост со временем |
| **UDMA_CRC_Error_Count** RAW | **0** | Рост → **кабель SATA**, порт, контроллер |
| **Raw_Read_Error_Rate** RAW | 0 или низкий, VALUE≈100 | VALUE падает к Threshold |
| **Read_Error_Retry_Rate** RAW | Зависит от прошивки; смотреть **тренд** | Резкий рост + падение VALUE |

Полный отчёт (для архива): `smartctl -a "$DISK" > ~/smart-netacA-$(date +%F).txt`

**Инцидент 2026-05-30:** ZFS SUSPENDED, 118 WRITE errors на устройстве, после reboot pool ONLINE, SMART PASSED, realloc=0. Имеет смысл **раз в месяц** повторять SMART и не игнорировать повторный SUSPENDED.

### 3.4. Scrub (раз в квартал)

```bash
zpool scrub netacA
# прогресс:
zpool status netacA
```

Scrub на 4 TB может идти **несколько часов**; во время scrub LLM лучше не гонять тяжёлую модель, если диск уже «капризничал».

### 3.5. Место под модели

```bash
zfs list netacA/llm-shared
df -h /mnt/llm-shared
du -sh /mnt/llm-shared/models /mnt/llm-shared/hf 2>/dev/null
```

Политика: веса на **shared dataset**, бэкап — snapshot/rsync на **внешний носитель** (§3.6), не полагаться только на один диск без зеркала.

### 3.6. Бэкап на внешний носитель (вручную)

ZFS на **одном** SATA **не** заменяет копию «в другом месте». Ни scrub, ни SMART PASSED не спасут от внезапной смерти диска. Ниже — **ручной** сценарий без Proxmox Backup Server и без cron: раз в квартал (или сразу после инцидента §3.3) — **USB HDD/SSD**, подключённый к **хосту PVE** или к **ноутбуку** через сеть.

#### Что копировать (приоритет)

| Приоритет | Что | Где на сервере | Зачем |
|-----------|-----|----------------|-------|
| **1** | Модели, HF-кэш, Ollama blobs | `/mnt/llm-shared/` (`models/`, `hf/`, `ollama/`, …) | Долго качается заново; главная ценность |
| **2** | Конфиги Proxmox и CT | `/etc/pve/lxc/*.conf`, `/etc/pve/qemu-server/`, `/etc/gpu-mutex/`, `/var/lib/vz/snippets/` | Восстановить VMID, GPU, bind `mp0` |
| **3** | Скрипты deploy на PVE | `~/llm-gpu-setup/` на хосте; локальный `pve-deploy.env` (не в git) | Повтор deploy clone / template |
| **4** | Rootfs CT (без дубля моделей) | `vzdump` CT **101** / **102** *или* snapshot subvol rootfs | venv, systemd units, `vllm.env` |
| **5** | Система PVE (NVMe) | список пакетов, `/etc/network/interfaces`, `/etc/pve/storage.cfg`, ключи SSH | Полная переустановка хоста редка; достаточно «как поднять с нуля» из git |

**Не обязательно** каждый раз: полный `zfs send` всего pool `netacA` (тяжело по объёму). Достаточно **`llm-shared` + конфиги**; веса при необходимости докачать с Hub/Ollama registry.

**Политика vzdump:** если `mp0` — bind на `/mnt/llm-shared`, в дамп CT **не** попадают модели на shared (это плюс). Бэкап rootfs CT — да; дублировать те же гигабайты rsync + vzdump не нужно.

#### Подготовка USB-диска

**На хосте PVE** (root, USB вставлен в сервер):

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
# найти, например, /dev/sdb (убедиться по MODEL/SIZE — не SATA 4TB!)
```

Новый диск — одна разделка **ext4** (просто монтировать и `rsync`):

```bash
DISK=/dev/sdb          # ПРОВЕРИТЬ lsblk — ошибка = потеря pool
PART=${DISK}1

parted -s "$DISK" mklabel gpt mkpart primary ext4 1MiB 100%
mkfs.ext4 -L homelab-backup "$PART"

mkdir -p /mnt/backup-usb
mount "$PART" /mnt/backup-usb
```

Метка тома **`homelab-backup`** — проще находить при следующем подключении. После работы:

```bash
sync
umount /mnt/backup-usb
```

**С ноутбука:** USB на рабочей станции, pull по SSH (§3.6.2) — не нужно физически лезть в сервер, если сеть быстрая и модели уже на shared.

#### 3.6.1. rsync с хоста PVE (USB на сервере)

Окно обслуживания: LLM лучше остановить (`pct stop 101` / `102`), чтобы файлы моделей не менялись mid-copy.

```bash
BACKUP=/mnt/backup-usb/homelab-$(date +%F)
mkdir -p "$BACKUP"/{llm-shared,pve-config,llm-gpu-setup}

# 1) Главное — shared dataset (модели, hf, ollama)
rsync -aH --info=progress2 --delete-delay \
  /mnt/llm-shared/ "$BACKUP/llm-shared/"

# 2) Конфиги PVE (pmxcfs — копируем с хоста как обычные файлы)
rsync -aH /etc/pve/lxc/ "$BACKUP/pve-config/lxc/"
rsync -aH /etc/gpu-mutex/ "$BACKUP/pve-config/gpu-mutex/" 2>/dev/null || true
rsync -aH /var/lib/vz/snippets/ "$BACKUP/pve-config/snippets/" 2>/dev/null || true
cp /etc/pve/storage.cfg "$BACKUP/pve-config/" 2>/dev/null || true

# 3) Скрипты deploy (если есть на хосте)
rsync -aH /home/guests/llm-gpu-setup/ "$BACKUP/llm-gpu-setup/" 2>/dev/null || true

# 4) Снимок метаданных (для журнала §10)
{
  echo "=== $(date -Is) ==="
  zpool list netacA
  zfs list netacA/llm-shared
  pct list
  du -sh /mnt/llm-shared/* 2>/dev/null
} > "$BACKUP/MANIFEST.txt"

sync
```

Флаг **`--delete-delay`**: на USB будет зеркало текущего `llm-shared` (удалённые на сервере файлы пропадут и в бэкапе). Если нужны **несколько поколений** — не используйте `--delete`, копируйте в каталог с датой (`homelab-2026-05-30`) и храните 2–3 последних.

#### 3.6.2. rsync с ноутбука (USB у себя, pull по SSH)

Удобно, если USB только на рабочей станции:

```bash
STAMP=$(date +%F)
DEST=~/backups/homelab-$STAMP
mkdir -p "$DEST"

rsync -aH --info=progress2 -e ssh \
  guests-pve:/mnt/llm-shared/ \
  "$DEST/llm-shared/"

rsync -aH -e ssh \
  guests-pve:/etc/pve/lxc/ \
  "$DEST/pve-config/lxc/"
```

К **`/etc/pve/`** с ноутбука нужен **root на PVE** — проще `pct exec` / `ssh root@…` или один раз `tar` на хосте:

```bash
# на PVE root:
tar -C /etc/pve -czf /tmp/pve-config-$(date +%F).tar.gz lxc storage.cfg
# затем scp с ноутбука:
scp -P 1234 guests@10.x.x.123:/tmp/pve-config-*.tar.gz ~/backups/
```

#### 3.6.3. ZFS snapshot → файл на USB (опционально)

Если нужен **консистентный** снимок dataset (модели не трогают во время `send`):

```bash
SNAP=netacA/llm-shared@backup-$(date +%F)
BACKUP=/mnt/backup-usb/homelab-$(date +%F)
mkdir -p "$BACKUP"

zfs snapshot "$SNAP"
zfs send "$SNAP" | gzip -1 > "$BACKUP/llm-shared.zfs.gz"

# список снапшотов (не копить вечно):
zfs list -t snapshot netacA/llm-shared
# удалить старый: zfs destroy netacA/llm-shared@backup-2026-01-01
```

Восстановление на **новый** pool/dataset (когда появится второй диск):

```bash
zfs receive -F netacA/llm-shared-restored < llm-shared.zfs.gz   # через gzip -dc
```

Для «просто пережить смерть SATA» чаще достаточно **rsync каталога** — проще проверить и выборочно достать файлы.

#### 3.6.4. vzdump rootfs CT (без моделей на shared)

Через GUI: **Datacenter → Backup** или в CLI на PVE:

```bash
# остановить CT — консистентнее; можно и live с --mode snapshot для LXC
pct stop 101
vzdump 101 --dumpdir /mnt/backup-usb/homelab-$(date +%F)/vzdump --mode stop
pct start 101
```

Аналогично **102** (Ollama), если уже в проде. Файлы `.vma.zst` — конфиг + rootfs CT, **не** `/mnt/llm-shared`.

#### 3.6.5. Проверка бэкапа

Минимум перед отключением USB:

```bash
# размеры сходятся порядка (не байт-в-байт из-за sparse/hardlinks)
du -sh /mnt/backup-usb/homelab-*/llm-shared
du -sh /mnt/llm-shared

# выборочно — есть ли известная модель
ls /mnt/backup-usb/homelab-*/llm-shared/models/
test -f /mnt/backup-usb/homelab-*/pve-config/lxc/101.conf && echo OK

# архив конфигов читается
tar -tzf ~/backups/pve-config-*.tar.gz | head
```

Запишите в §10: дата, объём USB, что копировали, `MANIFEST.txt`.

#### 3.6.6. Восстановление (кратко)

| Сценарий | Действие |
|----------|----------|
| Жив pool, потеряли только CT | `pct restore` из vzdump + bind `mp0` как в `101.conf` из бэкапа |
| Pool ONLINE, откатились модели | `rsync` с USB **на** `/mnt/llm-shared/` (сначала `pct stop` LLM-CT) |
| Pool мёртв, новый диск | Новый ZFS pool → dataset `llm-shared` → `rsync` с USB → правка `storage.cfg` / bind в CT |
| Только NVMe сгорел | Переустановка PVE по [instruction.md](instruction.md) → pool на SATA если жив → иначе восстановление с USB |

После восстановления моделей: `systemctl start vllm` / `ollama list`, smoke API (см. [05 — Ollama operations](05-ollama-operations.md)).

#### 3.6.7. Ограничения «ручного» бэкапа

- USB **отключён** большую часть времени — защита от ransomware на LAN, но нет непрерывности RPO.
- Один диск USB **тоже** может умереть — раз в год второй носитель или облако **без** секретов (только веса, если приемлемо).
- **Не** храните на USB единственную копию `pve-deploy.env` с паролями — env держите локально, вне публичного git.
- Бэкап **во время** тяжёлого inference — риск inconsistent files; останавливайте CT или используйте ZFS snapshot (§3.6.3).

---

## 4. Системный NVMe (Proxmox, `local` / `local-lvm`)

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
df -h /
pvesm status
```

При нехватке места на **local** для ISO/template: чистка `pveam list` / старых backup в GUI, не забивать корень логами.

---

## 5. NVIDIA RTX 3060 (LLM на хосте / LXC)

### 5.1. Хост PVE

```bash
nvidia-smi
lsmod | grep nvidia
ls -l /dev/nvidia*
dmesg | grep -iE 'nvidia|gpu|xid' | tail -20
```

| Симптом | Что проверить |
|---------|----------------|
| **Xid** в dmesg | Драйвер, питание GPU, перегрев, vLLM OOM |
| Нет `/dev/nvidia-uvm` | `modprobe nvidia_uvm` |
| Driver/library mismatch в CT | Версия user-space в CT = хост (§5.2, runbook `03b` в репо) |

Зафиксированная линия: **595.71.05**, CUDA **13.2** (май 2026).

### 5.2. Внутри CT 101 (vLLM)

```bash
ssh guests-101 'nvidia-smi; systemctl status vllm --no-pager'
journalctl -u vllm -n 30 --no-pager   # на CT под root или через pct exec
```

Память GPU при работающей модели: в `nvidia-smi` смотреть **Memory-Usage**; в LXC список **Processes** может быть пустым — ориентир MiB + логи vLLM.

### 5.3. Температура и лимит

```bash
nvidia-smi -q -d TEMPERATURE,POWER,CLOCK
```

При throttling / shutdown — пыль, вентиляторы, **`Power Limit`** в `nvidia-smi`.

### 5.4. После обновления драйвера на хосте

Цепочка: хост → пересборка template **900** → каждый clone из registry → **CT 101** вручную.
См. `infrastructure/proxmox-setup/03b-upgrade-nvidia-driver-chain.md` (в git; обезличенные IP).

---

## 6. AMD RX 550 (консоль хоста)

```bash
lspci | grep -i vga
dmesg | grep -i amdgpu | tail -15
```

Используется для вывода консоли, когда **3060** занята LLM. При чёрном экране BIOS/GRUB — кабель монитора на RX 550.

---

## 7. Память (96 GiB)

### 7.1. Быстрая проверка под нагрузкой

```bash
free -h
grep -E 'MemTotal|MemAvailable|SwapTotal' /proc/meminfo
```

На хосте с ZFS **available** может быть маленьким — это нормально (ARC). Смотреть **MemAvailable** и swap.

### 7.2. Ошибки ECC / MCE

```bash
dmesg | grep -iE 'hardware error|mce|edac|memory'
journalctl -k -b | grep -iE 'mce|memory'
```

### 7.3. Memtest (редко, при подозрении)

Требует **reboot** в memtest86+ из BIOS/GRUB — планировать окно простоя. Для Ryzen без ECC — раз в год или после непонятных kernel panic.

---

## 8. CPU, температура, питание

```bash
lscpu | grep -E 'Model name|CPU\(s\)|MHz'
# sensors (если установлен lm-sensors):
sensors 2>/dev/null || apt install -y lm-sensors && sensors-detect  # один раз
```

Перегрев → троттлинг → нестабильность под длительным vLLM. Пыль на кулере 3900X — типичная причина.

---

## 9. Proxmox и гости

```bash
pveversion -v
pct list
systemctl status pve-cluster pvedaemon pveproxy --no-pager
```

| VMID | Роль |
|------|------|
| 100 | тестовый CT |
| 101 | vLLM (legacy, не из template) |
| 900 | template `llm-gpu-base` |
| 102+ | clone (Ollama, …) — см. `/etc/llm-gpu/clones.registry` |

**GPU mutex:** только один GPU-CT из группы running — `/etc/gpu-mutex/group.conf`.

После обновления **Proxmox**:

```bash
pveversion
zpool status netacA
pct start 101
# smoke vLLM API
```

---

## 10. Журнал инцидентов и проверок (заполнять вручную)

| Дата | Событие / проверка | Итог |
|------|-------------------|------|
| 2026-05-30 | ZFS SUSPENDED, 118 WRITE; reboot; SMART PASSED | pool ONLINE, продолжить template |
| | | |

---

## 11. Связанные файлы и скрипты

| Где | Что |
|-----|-----|
| `~/llm-gpu-setup/scripts/pve/host-prep-check.sh` | Preflight перед template |
| `~/llm-gpu-setup/scripts/pve/zfs-recover-pool.sh` | SUSPENDED pool (осторожно с export) |
| [instruction.md](instruction.md) | §11.2a — shared `llm-shared`, политика vzdump |
| §3.6 этого файла | Бэкап на внешний USB вручную |
| [03b — NVIDIA driver chain](03b-upgrade-nvidia-driver-chain.md) | Драйвер NVIDIA |
| [scripts/audit-as-built.sh](scripts/audit-as-built.sh) | Снимок с ноутбука (`--clones`) |
| [05 — Ollama operations](05-ollama-operations.md) | API, mutex, модели |
| [06 — Ollama inference](06-ollama-inference-settings.md) | Контекст, thinking |

---

## 12. Когда не чинить «на месте»

- Повторный **SUSPENDED** на `netacA` за короткий срок → SMART + **замена SATA-кабеля**, другой порт, **§3.6** (бэкап на USB), рассмотреть зеркало/второй диск.
- **SMART FAILED** или растущий **Reallocated_Sector_Ct** → не расширять pool, **сразу** §3.6 (копия `/mnt/llm-shared` на USB), рассмотреть замену диска.
- Зависание **`pct stop`** / **`zpool export`** при SUSPENDED → **reboot**, не ждать Ctrl+C.
- Странные **Xid** NVIDIA + артефакты в выводе → снизить нагрузку, проверить температуру, версию драйвера.
