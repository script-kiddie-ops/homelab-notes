# Proxmox VE 9.1 — пошаговая установка “для домохозяек” (RU)

Ниже — **чёткие фазы**. Делайте по порядку. Если на шаге что-то не совпадает — **не “чините наугад”**, остановитесь и сверяйтесь с разделом **“Быстрые проверки/типовые проблемы”** в конце.

## Что у нас есть (зафиксировано)
- **Плата/CPU/RAM**: ASRock B550M Steel Legend, Ryzen 3900, 96GB RAM.
- **Диски**:
  - NVMe 240GB — под систему Proxmox, **ext4**.
  - SATA SSD 4TB — под ВМ/контейнеры, **ZFS (один диск, без зеркала)**. Диск можно **полностью стереть**.
- **Сеть**:
  - Ethernet (Realtek RTL8125 / `r8169`) — **основной**.
  - USB Wi‑Fi (rtl8xxxu) — **резерв**.
- **Требование по доступу**: привычный порт и пользователь; **финал** — только SSH-ключи, пароль выключен (см. [ssh_notes.md](ssh_notes.md), §7.4):
  - установка: `ssh -p 1234 guests@10.x.x.225` (пароль временно, фаза 7);
  - эксплуатация: `ssh guests-pve` / `ssh guests-101` → `10.x.x.123` / `10.x.x.101`, `PasswordAuthentication no`.
- **Видеокарты** (разъёмы платы см. мануал ASRock B550M Steel Legend):
  - **GeForce RTX 3060 12GB** — строго в верхний слот **PCIE1** (PCIe **4.0 ×16**). Под LLM и/или (опционально) passthrough в игровую VM.
  - **AMD Radeon RX 550 2GB** — в нижний слот **PCIE3** (PCIe **3.0 ×4**). Консоль хоста при сценарии «3060 ушла в VM»; драйвер **`amdgpu`**.

## Важное предупреждение (1 раз прочитать)
- Установка Proxmox **перезапишет NVMe**.
- Создание ZFS-пула на SATA SSD **перезапишет SATA 4TB**.
- ZFS на одном диске **не защищает от отказа диска**. Бэкапы обязательны.

--- 

## Фаза 0. Подготовка (5–20 минут)

### 0.1. Подготовьте физический доступ
- Подключите к серверу **монитор** и **клавиатуру**.
- Подключите **Ethernet кабель** в роутер/свитч.

### 0.2. Подготовьте флешку с Proxmox VE 9.1 ISO
- Скачайте ISO Proxmox VE 9.1 (с официального сайта).
- Запишите на USB флешку (Rufus/Etcher/`dd` — чем привычнее).

### 0.3. Решите, как сохранить IP `10.x.x.225`
Есть два варианта. Выберите один (любой рабочий):

- **Вариант A (предпочтительный, “чтобы не ошибиться”)**: сделать **DHCP reservation** на роутере.
  - В интерфейсе роутера найдите раздел вроде “DHCP / Address Reservation”.
  - Добавьте правило: **MAC Ethernet** → **`10.x.x.225`**.
  - Плюс: меньше риска ошибиться в маске/gateway/DNS.
- **Вариант B**: прописать **статический IP** прямо в установщике Proxmox.
  - Нужно знать: маску (обычно `/24`), gateway (обычно `10.x.x.1`) и DNS.

Если не уверены — делайте **Вариант A**.

---

## Фаза 1. BIOS/UEFI (5 минут)
Цель: включить аппаратную виртуализацию и нормальную UEFI-загрузку.

1) Перезагрузите сервер.
2) При старте нажимайте `Del` (или `F2`), чтобы войти в BIOS/UEFI.
3) Найдите и проверьте настройки (названия могут чуть отличаться):
   - **SVM Mode / AMD-V** → `Enabled`
   - **IOMMU** → `Enabled`
   - **Above 4G Decoding** → `Enabled` (рекомендуется с двумя GPU и для passthrough)
   - **UEFI Boot** → `Enabled`
   - **CSM / Legacy** → `Disabled` (если нет причины держать)
   - **Resizable BAR / Re-Size BAR** → сначала **`Disabled`** или `Auto`; включать позже по желанию
   - **Secure Boot**:
     - можно оставить `Enabled`;
     - если потом будут проблемы с загрузкой — временно поставим `Disabled`.
   - **Про приоритет видеокарты (Primary GPU)**: на части плат этого **пункта нет** — это нормально. Куда воткнут монитор, та карта и становится «рабочим дисплеем» для сессии (для POST/BIOS обычно тоже можно выбрать порт на активной карте). Если планируете **passthrough 3060 в VM**, кабель монитора для консоли хоста переводите на **RX 550**.
4) Сохраните изменения (`F10` → Yes) и перезагрузитесь.

---

## Фаза 2. Установка Proxmox VE 9.1 на NVMe (15–30 минут)
Цель: поставить Proxmox на NVMe и сразу получить веб‑панель.

1) Загрузитесь с флешки Proxmox.
2) Выберите **Install Proxmox VE**.
3) На шаге выбора диска выберите **NVMe 240GB**.
4) В “Options/Advanced Options” (если есть) выберите файловую систему **ext4**.
5) Введите:
   - пароль `root` (запишите!)
   - e‑mail
6) Шаг сети:
   - выберите **Ethernet** интерфейс (встроенный Realtek).
   - задайте hostname (любой, например `pve-home`).
   - IP:
     - если делали **DHCP reservation** → можно оставить DHCP;
     - иначе задайте статикой **`10.x.x.225/24`**.
   - gateway: обычно `10.x.x.1`
   - DNS: ваш роутер (`10.x.x.1`) или публичный (1.1.1.1/8.8.8.8).
7) Дождитесь окончания установки.
8) После установки извлеките флешку и перезагрузитесь.

### 2.1. Первый вход в веб‑интерфейс
С вашего ПК (в той же сети) откройте:
- `https://10.x.x.225:8006`

Войдите:
- user: `root`
- realm: `pam`
- password: тот, что задавали

---

## Фаза 3. Сеть в Proxmox (Ethernet bridge) (5–10 минут)
Цель: `vmbr0` мостит Ethernet, чтобы ВМ/контейнеры получали IP в домашней сети.

1) В веб‑панели Proxmox: **Datacenter → Node (ваш) → System → Network**.
2) Должно быть примерно так:
   - `vmbr0` (Linux Bridge)
   - у `vmbr0` есть **Bridge ports** = ваш Ethernet интерфейс (что-то вроде `enpXsY`).
   - IP `10.x.x.225/24` висит на `vmbr0`.
3) Если IP висит на физическом интерфейсе, а `vmbr0` пустой:
   - не “крутите” наугад — лучше следовать официальной логике: **IP должен быть на `vmbr0`**, а физический интерфейс — в bridge ports.

Примечание: Wi‑Fi **не пытайтесь** добавлять в `vmbr0` как bridge port. Держим его резервом.

---

## Фаза 4. Обновление Proxmox после чистой установки (5–15 минут)
Цель: сразу быть на актуальных пакетах.

### 4.0. Репозитории без платной подписки Enterprise (домашний сервер)

По умолчанию Proxmox настроен на репозиторий **`pve-enterprise`**. Без ключа подписки `apt update` будет **жаловаться** — это нормально, пока не переключите репозитории.

1) **Отключите enterprise-источник** (любой удобный способ):
   - на свежих установках файл может называться **`pve-enterprise.sources`** (формат DEB822), а не `pve-enterprise.list` — суть та же;
   - **переименуйте** файл (проще откатить):  
     `sudo mv /etc/apt/sources.list.d/pve-enterprise.sources /etc/apt/sources.list.d/pve-enterprise.sources.bak`  
     (если у вас всё же **`.list`** — то же самое с `pve-enterprise.list` → `.bak`);
   - либо **закомментируйте все строки** в этом файле (`#`);
   - либо в DEB822-блоке добавьте **`Enabled: no`** (если ваша версия `apt` это понимает — см. `man sources.list`).

2) **Добавьте бесплатную ветку `pve-no-subscription`**. Актуальную строку и пояснения возьмите из официальной вики:  
   [Package Repositories](https://pve.proxmox.com/wiki/Package_Repositories)  
   для вашей версии PVE и базы Debian (у **PVE 8 / 9** это обычно **`bookworm`**). Пример записи (проверьте по вики, не копируйте вслепую, если выйдет новый релиз):

```bash
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
```

3) Убедитесь, что интернет с хоста есть, затем обновление (см. ниже).

Если когда‑нибудь купите **Enterprise** — можно вернуть `pve-enterprise` и убрать `no-subscription` по политике Proxmox.

### 4.1. Обновление пакетов

В веб‑панели:
- **Node → Updates** → Refresh → Upgrade

Или в консоли хоста:

```bash
apt update
apt dist-upgrade -y
reboot
```

---

## Фаза 5. ZFS на SATA SSD 4TB (10–20 минут)
Цель: создать ZFS‑пул под VM/CT и ограничить ARC до ~8GB.

### 5.1. Убедиться, что вы выбрали правильный диск
В веб‑панели:
- **Node → Disks**: найдите SATA SSD 4TB (Netac).

### 5.2. Создать ZFS пул (1 диск)
В веб‑панели обычно есть мастер создания ZFS.
- Создайте **ZFS pool** на SATA SSD 4TB.
- Тип: **single disk** (без mirror/raidz).

### 5.3. Базовые свойства ZFS (рекомендуемые)
Проверьте/выставьте для пула/датасетов (через GUI или CLI):
- `compression=lz4`
- `atime=off`
- `autotrim=on`

### 5.4. Ограничить ARC до ~8GB
Цель: ограничить ZFS‑кеш в RAM.

Обычно это делают через параметр модуля ZFS (`zfs_arc_max`) и обновление initramfs.
Команды (делайте после того, как Proxmox установлен и работает стабильно):

```bash
echo "options zfs zfs_arc_max=8589934592" > /etc/modprobe.d/zfs.conf
update-initramfs -u
reboot
```

Проверка после перезагрузки:

```bash
cat /sys/module/zfs/parameters/zfs_arc_max
```

---

## Фаза 6. Добавить ZFS как Storage для ВМ/контейнеров (5 минут)
Цель: Proxmox должен “видеть” ваш ZFS и уметь складывать туда диски ВМ.

В веб‑панели:
- **Datacenter → Storage → Add → ZFS**
- Выберите ваш pool.
- Включите хранение **Disk image** (и при необходимости **Container**).

---

## Фаза 7. SSH “как раньше” (IP .225 и порт 1234) (10–20 минут)
Цель: чтобы `ssh -p 1234 guests@10.x.x.225` снова работал.

### 7.1. Понять важное про Proxmox и SSH
Proxmox — это Debian, SSH на нём обычный `sshd`.

### 7.2. Сменить порт SSH на 1234
1) Зайдите на Proxmox по SSH на стандартный порт (первый раз):

```bash
ssh root@10.x.x.225
```

2) Отредактируйте `/etc/ssh/sshd_config` и задайте порт 1234:
- найдите строку `#Port 22` и сделайте `Port 1234`
- (по желанию) оставьте и 22, и 1234 на время “переезда”:
  - `Port 22`
  - `Port 1234`

3) Перезапустите SSH:

```bash
systemctl restart ssh
```

4) Проверьте вход:

```bash
ssh -p 1234 root@10.x.x.225
```

Когда убедитесь, что 1234 работает — можно убрать порт 22 (по желанию).

### 7.3. Создать пользователя `guests` и **временно** включить пароль (этап 1)
Нужно только чтобы один раз сработал **`ssh-copy-id`**. Подробный дневник — [ssh_notes.md](ssh_notes.md).

1) Создать пользователя:

```bash
adduser guests
```

2) Дать права админа (опционально, если нужно):

```bash
usermod -aG sudo guests
```

3) В `/etc/ssh/sshd_config` на время настройки ключей:
   - `Port 1234`
   - `PermitRootLogin no`
   - **`PasswordAuthentication yes`** (временно)
   - права `~guests/.ssh` — **700**, `authorized_keys` — **600**

4) Перезапустить SSH (и при необходимости `ssh.socket` / `listen.conf` — см. ssh_notes):

```bash
systemctl restart ssh
```

5) Проверка с ПК:

```bash
ssh -p 1234 guests@10.x.x.225
```

6) С ноутбука: `ssh-copy-id` на хост и CT, алиасы `guests-pve` / `guests-101` в `~/.ssh/config` — см. ssh_notes.

**Не останавливайтесь на этом шаге** — сразу выполните §7.4 на каждом узле.

### 7.4. Отключить пароль после ключей (этап 2, боевое состояние)
На **хосте Proxmox** и в **CT 101** (и на любом новом госте с SSH):

1) В `/etc/ssh/sshd_config` выставить:

```text
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
```

2) Проверить и перезапустить:

```bash
sshd -t && systemctl restart ssh
```

3) Убедиться, что в `/etc/ssh/sshd_config.d/` нет переопределения `PasswordAuthentication yes` или `PubkeyAuthentication no`.

4) С ноутбука: `ssh guests-pve` и `ssh guests-101` без запроса пароля.

Полный пример блока `sshd_config` — [ssh_notes.md](ssh_notes.md) (раздел «Этап 2»).

---

## Фаза 8. Минимальные проверки “всё работает” (5–15 минут)

### 8.1. Проверка Proxmox
- Веб‑панель открывается: `https://10.x.x.225:8006`
- Обновления поставились, после `reboot` хост поднялся.

### 8.2. Проверка сети для ВМ
Создайте тестовую VM или LXC и подключите к `vmbr0`.
- Она должна получить IP в `10.x.x.0/24` (через DHCP роутера) **или** вы задаёте статически.
- Должен быть интернет.

### 8.3. Проверка ZFS
- Пул виден в Storage.
- Создание диска ВМ на ZFS проходит без ошибок.

---

## Фаза 9. Проверить GPU в Linux (до или сразу после Proxmox)

Цель: убедиться, что обе карты видны, **3060 на полной полосе PCIe**, RX 550 корректно в своём слоте.

1) Список VGA:
```bash
lspci -nn | egrep -i 'vga|3d|display'
```
2) Драйверы:
```bash
lspci -nnk | egrep -i 'vga|3d|display|Kernel driver in use|Kernel modules' -A2
```
Ожидаемо: RX 550 → **`amdgpu`**; RTX 3060 до установки NVIDIA часто → **`nouveau`**.

3) Проверить линк **RTX 3060** (подставьте bus-id из `lspci`, например `06:00.0`):
```bash
sudo lspci -s 06:00.0 -vv | egrep -i 'LnkCap|LnkSta'
```
Цель: **`Speed 16GT/s`** и **`Width x16`** (PCIe Gen4 ×16 для PCIE1 на Ryzen Matisse).

4) Проверить линк **RX 550** (например `04:00.0`):
```bash
sudo lspci -s 04:00.0 -vv | egrep -i 'LnkCap|LnkSta'
```
В слоте PCIE3 нормально видеть **×4** по ширине; скорость при простое может «проседать» из‑за энергосбережения — при сомнении:
```bash
cat /sys/bus/pci/devices/0000:04:00.0/current_link_speed
cat /sys/bus/pci/devices/0000:04:00.0/current_link_width
```

5) Если к RX 550 **нет монитора**, в `dmesg` у amdgpu часто бывают строки **`Cannot find any crtc or sizes`** — при выводе через 3060 это **ожидаемо**, не означает поломку RX 550.

---

## Фаза 10. NVIDIA на хосте Proxmox (для LLM, не для VFIO)

Цель: после стабильной установки и обновления PVE — **`nvidia-smi`**, модули **`nvidia`** / **`nvidia_uvm`**, устройства **`/dev/nvidia*`**.

- Выполняйте **после** того, как базовая система, сеть, ZFS и SSH в порядке (чтобы не усложнять отладку).
- Используйте **официальные рекомендации** Proxmox/Debian для установки **proprietary NVIDIA** под ваше ядро (пакеты/репозиторий — уточним на шаге исполнения под актуальный PVE).
- До установки драйвера **`nvidia-smi` отсутствует** и загружен **`nouveau`** — это нормальная стартовая точка.

После установки:
```bash
nvidia-smi
lsmod | egrep '^nvidia'
ls -l /dev/nvidia*
```

---

## Фаза 11. LXC под LLM и доступ к GPU

Цель: **привилегированный** LXC с диском на **ZFS storage**, сетью **`vmbr0`**, bind-mount устройств **`/dev/nvidia*`** и правилами **cgroup v2**, чтобы внутри CT работала **`nvidia-smi`** (ещё до установки vLLM).

**Не смешивать** одновременно: этот сценарий (NVIDIA на хосте + LXC) и **VFIO passthrough той же 3060** в VM — для одной карты это взаимоисключающие конфигурации.

### 11.1. Предпосылки на хосте Proxmox

- Уже выполнена **Фаза 10**: `nvidia-smi` на хосте показывает драйвер и GPU, в `lsmod` есть **`nvidia`**, **`nvidia_uvm`**, в **`/dev`** есть узлы **`nvidia*`**.

### 11.2. Создание контейнера (первый раз — через GUI)

В веб‑интерфейсе: **Create CT**.

- **Privileged container**: **да** (unprivileged + NVIDIA в домашнем сценарии заметно сложнее).
- **Hostname / пароль root**: по желанию.
- **Storage**: корень CT на вашем **ZFS** storage (например `netacA` или как назвали пул в PVE).
- **Шаблон**: **Debian 13 (trixie)** или **Ubuntu 24.04** — оба подходят; для **pip wheel’ов PyTorch/vLLM** иногда проще **Ubuntu**, для полного совпадения с хостом PVE чаще берут **Debian**. Если сомневаетесь — **Ubuntu 24.04 LTS** как менее капризный вариант для Python‑стека.
- **Сеть**: мост **`vmbr0`**, IPv4 через DHCP роутера или статика в вашей подсети (например `10.x.x.0/24`).
- **Features**: при желании **`nesting=1`**, если позже понадобятся вложенные сценарии; для GPU не обязательно.

#### Диски: rootfs и отдельный том под модели / Hugging Face

Рекомендуемая схема для **vLLM** (тяжёлый venv на root, большие данные отдельно):

1. **Корневой диск (rootfs)** — на вашем **ZFS** storage (тот же пул, например **`netacA`**), размер **64 GiB**: ОС, `apt`, Python **venv**, wheel’ы PyTorch/vLLM, логи. **Не переносите rootfs на `local-lvm`**, если там мало места (типично мелкий NVMe под систему PVE): корню CT лучше место на **ZFS**, где пул большой.
2. Второй том (**Mount point** в мастере, в конфиге часто **`mp0`**) — тоже на **ZFS `netacA`**, размер **128 GiB** (или больше, если моделей много): только **веса моделей**, **кэш Hugging Face**, датасеты. Путь монтирования внутри CT задайте осмысленным, например **`/srv/llm`** (не оставляйте дефолт вроде `/mnt/mp0`, чтобы не плодить разные пути в сервисах). Внутри после первого входа: `mkdir -p /srv/llm/models /srv/llm/hf` и в окружении vLLM задайте **`HF_HOME=/srv/llm/hf`** (при необходимости **`TRANSFORMERS_CACHE`** — туда же или подкаталог).
3. **Галочка Backup** у **`mp0`**: для больших воспроизводимых весов и кэша HF часто **снимают** (бэкапят **rootfs** и отдельно копируют модели/rsync по политике). Включайте backup на **`mp0`**, только если нужен **полный vzdump** контейнера «со всем» и устраивают размер и время бэкапа.

**Если планируете несколько CT с одними весами** (по очереди, не параллельно на GPU) — лучше сразу **общий ZFS dataset на хосте** (§11.2a), а не отдельный zvol/subvol на каждый CT.

Запустите CT и зайдите в консоль PVE или по SSH: `ssh root@<IP_CT>`.

### 11.2a. Общее хранилище LLM на ZFS (shared storage) — несколько CT, одни веса

**Да:** «общий ZFS dataset на хосте» = **shared storage**: один каталог на пуле **ZFS**, смонтированный на **Proxmox**, в каждый CT подключается как **bind mount** (в Proxmox — **Mount point** с путём **на хосте**).

#### Политика использования

- **Веса и HF-кэш** — **одна копия** на диске, путь в CT везде одинаковый: **`/srv/llm`** (`models/`, `hf/`).
- **Несколько CT** могут **по очереди** использовать те же файлы (разные движки: vLLM, llama.cpp, Ollama, **NVIDIA Triton Inference Server** и т.д.).
- **GPU (одна 3060)** — в один момент времени **один** тяжёлый инференс (один CT с загруженной моделью в VRAM). Второй CT с GPU лучше **остановить** или не запускать сервис, пока первый работает.
- **Параллельно** два CT на одной 3060 — не планируем (OOM / конфликт).

#### Разные движки — одни и те же файлы?

**Общая папка — да, «та же модель без конвертации» — не всегда.**

| Формат на диске | Типично кто читает | Примечание |
|-----------------|-------------------|------------|
| **Hugging Face layout** (`config.json`, `*.safetensors`, tokenizer) | **vLLM**, TGI, часть Ollama (import), transformers | То, что вы скачали **`hf download … --local-dir /srv/llm/models/...`**. **Triton** сырой HF-каталог **не** подхватывает — нужен экспорт (см. строку ниже). |
| **Triton model repository** (`config.pbtxt`, каталоги версий под backend: ONNX, TensorRT, TensorRT-LLM, Python и т.д.) | **NVIDIA Triton Inference Server** | Отдельная подготовка **model repository** (часто **`/srv/llm/models/triton/<model_name>/<version>/`**). Исходный HF можно хранить рядом в **`models/<имя>/`**, но для Triton — своя сборка/конвертация. |
| **GGUF** (один/несколько `.gguf`) | **llama.cpp**, часть Ollama | Отдельный файл или подкаталог, например **`/srv/llm/models/foo/model.gguf`**. |
| **Ollama blobs** | **Ollama** по умолчанию | Часто свой store; HF-папку можно подключать через **Modelfile** / import — отдельная настройка. |

Имеет смысл хранить в **`/srv/llm/models/<имя>/`** HF-снимки для vLLM, при необходимости **рядом** GGUF для llama.cpp (`<имя>-gguf/`) и отдельный подкаталог **model repository** для **Triton** (`triton/<имя>/`) — **без дублирования** лишних копий HF, если конвертацию делали осознанно.

**`HF_HOME=/srv/llm/hf`** — общий кэш Hub для всех CT; **одновременно** пусть качает модели **только один** CT.

#### Структура на хосте (целевая)

```
/mnt/llm-shared/          ← ZFS dataset netacA/llm-shared
  models/                 ← веса (HF, GGUF, …)
  hf/                     ← HF_HOME (hub, datasets)
```

В каждом CT: **mount** ` /mnt/llm-shared` → **`/srv/llm`** (те же пути, что уже в **`vllm.env`**).

#### Шаг A. Создать dataset на **хосте PVE** (один раз)

```bash
# подставьте имя своего пула, если не netacA
POOL=netacA

zfs create -o mountpoint=/mnt/llm-shared -o compression=lz4 -o atime=off "${POOL}/llm-shared"
mkdir -p /mnt/llm-shared/models /mnt/llm-shared/hf/hub
chmod 755 /mnt/llm-shared /mnt/llm-shared/models /mnt/llm-shared/hf
```

Проверка: **`zfs list`**, **`ls /mnt/llm-shared`**.

#### Шаг B. Миграция с текущего CT **101** (отдельный subvol `mp0` → shared)

Сейчас у **101** в конфиге обычно: **`mp0: netacA:subvol-101-disk-1,mp=/srv/llm,...`**. Перенос **без повторной загрузки с Hub**:

1. В **CT 101**: `systemctl stop vllm` (если включён).
2. На **хосте**: `pct stop 101`.
3. Смонтировать старый subvol на хосте и скопировать данные:

```bash
POOL=netacA
DATASET="${POOL}/subvol-101-disk-1"
MNT=/mnt/migrate-101-llm

mkdir -p "$MNT"
# subvol CT в Proxmox часто с mountpoint=none — временно вешаем на хост:
zfs set mountpoint="$MNT" "$DATASET"
zfs mount "$DATASET"

rsync -aH --info=progress2 "${MNT}/" /mnt/llm-shared/

zfs umount "$DATASET"
zfs set mountpoint=none "$DATASET"
```

Если **`mount -t zfs …`** пишет **canonicalization error: No such file or directory** — чаще всего **нет каталога** точки монтирования (проверьте имя: **`migrate-101-llm`**, не `…-ll`) или subvol ещё смонтирован иначе; используйте команды **`zfs set mountpoint`** выше.

4. Правка **`/etc/pve/lxc/101.conf`**: **заменить** строку **`mp0:`** на bind с хоста:

```
mp0: /mnt/llm-shared,mp=/srv/llm
```

(строку вида **`mp0: netacA:subvol-101-disk-1,...`** **удалить**).

5. `pct start 101` — внутри проверить: **`ls /srv/llm/models`**, **`nvidia-smi`**, **`systemctl start vllm`**.

6. Когда убедитесь, что всё на месте — освободить место (опционально, **необратимо**):

```bash
zfs destroy "${POOL}/subvol-101-disk-1"
```

#### Шаг C. Новый CT в будущем (тот же shared storage)

При создании CT:

- **rootfs** — по-прежнему свой subvol на ZFS (**64 GiB** и т.д.).
- Второй **Mount point**: не новый 128 GiB zvol, а **bind**:
  - **Storage**: bind / host path (в GUI: **Directory** или raw в conf),
  - **Path на хосте**: `/mnt/llm-shared`,
  - **Path в CT**: `/srv/llm`.

В **`/etc/pve/lxc/<VMID>.conf`**:

```
mp0: /mnt/llm-shared,mp=/srv/llm
```

Плюс для LLM-CT — те же **`lxc.mount.entry`** / **`cgroup2`** для NVIDIA (§11.4), **`hookscript: local:snippets/gpu-mutex.sh`** (§11.2a, GPU mutex). В **`vllm.env`** (или аналоге) те же **`MODEL_PATH`**, **`HF_HOME`**.

**Правило:** пока один CT гоняет модель на **3060**, другой LLM-CT с GPU — **не стартовать** (или без GPU — только чтение файлов). Для автоматизации — **hookscript** в §11.2a.

#### Бэкапы

- Удобно бэкапить **dataset** `llm-shared` (ZFS snapshot / `zfs send`) **один раз** на все модели.
- **vzdump** отдельных CT **без** дублирования весов, если **`mp0`** — bind на shared, а не отдельный диск с моделями.

#### GPU mutex: не больше одного гостя из группы (hookscript)

В Proxmox **нет** отдельной галочки «взаимоисключающая группа» в GUI. Чтобы **не запустить два CT/VM с GPU одновременно** (даже случайно из веб-интерфейса), на **каждого** гостя из группы вешают **hookscript** с фазой **`pre-start`**: если другой ID из списка уже **running** — старт **отменяется**.

Это дополняет правило «по очереди» выше; hook **не смотрит в VRAM**, только **кто из группы уже запущен**.

**1. Список VMID на хосте PVE** (файл на **обычной ФС**, не в **`/etc/pve/`** — там **pmxcfs**, `install`/`chmod` на произвольные пути часто дают *Operation not permitted*):

```bash
mkdir -p /etc/gpu-mutex
cat >/etc/gpu-mutex/group.conf <<'EOF'
# VMID гостей, которым разрешена одна 3060 (по одному running)
# LXC и QEMU — в одном списке
101
# 102
# 201
EOF
```

**2. Hookscript** (хранится в snippets, подключается как **`local:snippets/...`**):

```bash
# предпочтительно: скопировать из репо scripts/pve/gpu-mutex.sh
cp /path/to/repo/scripts/pve/gpu-mutex.sh /var/lib/vz/snippets/gpu-mutex.sh
chmod +x /var/lib/vz/snippets/gpu-mutex.sh
# group.conf: /etc/gpu-mutex/group.conf (редактировать здесь) или legacy /etc/pve/gpu-guests/group.conf
# hook читает оба пути; если ни одного файла нет — старт блокируется (exit 1), не «молча»
```

**3. Подключить ко всем гостям группы** — в **`/etc/pve/lxc/<VMID>.conf`** или **`/etc/pve/qemu/<VMID>.conf`**:

```
hookscript: local:snippets/gpu-mutex.sh
```

Или в GUI: **CT/VM → Options → Hookscript**.

Пример для **101** (рядом с **`mp0: /mnt/llm-shared,...`**):

```
hookscript: local:snippets/gpu-mutex.sh
mp0: /mnt/llm-shared,mp=/srv/llm
```

**4. Проверка:** при running **101** попытка **Start** другого ID из **`group.conf`** должна **завершиться ошибкой** в задаче Proxmox. После **Shutdown** первого — второй стартует.

**Быстрая установка из репозитория** (на машине с клоном, затем на **host** под **root**):

```bash
# с рабочей станции (подставьте путь к репо и пользователя SSH)
REPO=...
scp -P 1234 -r "$REPO/scripts/pve" guests@10.x.x.123:/tmp/gpu-mutex-install

# на хосте Proxmox
ssh -p 1234 guests@10.x.x.123
su -
bash /tmp/gpu-mutex-install/install-gpu-mutex.sh 101
```

Файлы в репо: **`scripts/pve/gpu-mutex.sh`**, **`gpu-guests-group.conf`**, **`install-gpu-mutex.sh`**. Повторный запуск **идемпотентен** (не дублирует hook).

**Ограничения:**

- Hook нужен **на каждом** члене группы; иначе «чужой» гость обойдёт проверку.
- Уже **два running** hook не остановит — только блокирует **новый** старт.
- Одновременный старт двух из GUI теоретически даёт гонку (на практике редко).
- Гость **без GPU** в той же группе тоже будет «mutex» — держите в списке **только** тех, кто реально использует **3060**.

### 11.3. Узнать major‑номера устройств на хосте

На **хосте** (не в CT):

```bash
ls -l /dev/nvidia*
```

Запомните **major** для символьных устройств (первая колонка после типа `c`). Часто встречается **195** (`nvidia0`, `nvidiactl`), **226** или **508/509** для MIG/новых схем, **234** для `nvidia-modeset` (для чистого compute можно не пробрасывать), **507/511** для **`nvidia-uvm`** (зависит от версии драйвера/ядра). **Ориентируйтесь на вывод своей машины**, а не на «магические числа из интернета».

Если есть **`/dev/nvidia-uvm-tools`**, его тоже учитывайте в allow‑правилах.

### 11.4. Фрагмент `/etc/pve/lxc/<VMID>.conf` на хосте Proxmox

Редактировать нужно на **Proxmox‑хосте** (либо **Datacenter → CT → Options**, если поле поддерживает многострочный raw, удобнее через SSH):

Добавьте в конец конфига CT (подставьте свой **VMID**; при необходимости добавьте/уберите строки под ваш **`ls -l`**):

```
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 234:* rwm
lxc.cgroup2.devices.allow: c 507:* rwm
lxc.cgroup2.devices.allow: c 511:* rwm
```

Пояснение:

- **`lxc.mount.entry`**: привязка узлов с хоста в CT.
- **`lxc.cgroup2.devices.allow`**: разрешение cgroup v2 на чтение/запись символьных устройств с указанными major; **`*`** в minor допустим для NVIDIA.

Если какого‑то файла **нет** на хосте (например `nvidia-uvm-tools`), **не добавляйте** для него `mount.entry` (или оставьте только существующие).

После правки:

```bash
pct stop <VMID> && pct start <VMID>
```

### 11.5. User-space NVIDIA внутри CT (должно совпасть с драйвером хоста)

Драйвер ядра работает на **хосте**; в CT нужны **совместимые библиотеки** той же ветки, что показывает **`nvidia-smi`** на хосте (строка *Driver Version*).

Пример для **Debian/Ubuntu** в CT:

1. Включите компонент **`non-free`** / **`non-free-firmware`** в `sources` (как на хосте, если драйвер с **backports** — добавьте и **`trixie-backports`** / **`noble-backports`** по аналогии).
2. Установите пакеты уровня **`nvidia-utils-<версия>`** или метапакет, который тянет **`libnvidia-*`** той же серии, что и хост (см. **`apt-cache policy nvidia-utils`** и сравните с хостом).

Проверка **внутри CT**:

```bash
nvidia-smi
```

Должны отображаться та же версия драйвера и GPU. Если **`Failed to initialize NVML`** — чаще всего не совпали **libs ↔ драйвер** или cgroup/маунты.

#### 11.5a. Если хост на драйвере из **CUDA repo** (например **595.x**), а CT — **Ubuntu 24.04**

Пакеты **`nvidia-utils-595`** из **Ubuntu** иногда **не совпадают по микроверсии** с ядром на PVE (**`Driver/library version mismatch`**). Рабочая схема (как в домашней установке):

1. В CT подключить **тот же** репозиторий, что и на хосте: **`https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/`** в **`/etc/apt/sources.list.d/`** с **`signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg`**.
2. Актуальный keyring: взять **`/usr/share/keyrings/cuda-archive-keyring.gpg`** с **хоста PVE** или распаковать из **`cuda-keyring_*.deb`** (`dpkg-deb -x …`), а не устаревшие URL **`*.pub`** (часто **404**).
3. Поставить user-space **той же версии**, что **`nvidia-smi` на хосте**, например: **`libnvidia-ml1`**, **`libcuda1`**, **`nvidia-driver-cuda`** (метапакет даёт **`nvidia-smi`**) с **`apt install -o APT::Install-Recommends=false`**, без **`nvidia-kernel-dkms`** в CT.
4. Зафиксировать пакеты, чтобы **`apt upgrade`** в CT не разъехался с хостом:  
   `dpkg-query -W -f='${Package}\n' | grep -E '^(libnvidia|nvidia-)' | xargs -r apt-mark hold`

---

## Фаза 12. vLLM как сетевой сервис (с первого дня) и опционально игры в VM

Целевой рантайм: **vLLM** в этом же LXC — **OpenAI‑совместимый HTTP API** для Python (OpenAI SDK, LangGraph и т.д.), **локальные веса** на диске CT или в заранее заполненном кэше Hugging Face.

### 12.0. Чеклист «с нуля» в CT (после рабочего `nvidia-smi`)

Выполняйте **внутри CT** под **root** (пути моделей подставьте свои).

```bash
# каталоги данных (см. §11.2: mp0 → /srv/llm)
mkdir -p /srv/llm/models /srv/llm/hf

# зависимости для Python / сборки части колёс
apt update
apt install -y python3 python3-venv python3-pip build-essential git

# venv
python3 -m venv /opt/vllm-venv
/opt/vllm-venv/bin/pip install -U pip wheel

# vLLM (версии при необходимости зафиксировать по документации vLLM под ваш драйвер/CUDA)
/opt/vllm-venv/bin/pip install vllm

# быстрый ручной тест (подставьте реальный путь к весам; хост 0.0.0.0 — только LAN)
/opt/vllm-venv/bin/vllm serve /srv/llm/models/<ВАША_МОДЕЛЬ> \
  --host 0.0.0.0 --port 8000 \
  --max-model-len 8192 --gpu-memory-utilization 0.90 --max-num-seqs 5
```

Если **`pip install vllm`** падает по **CUDA/torch** — откройте [vLLM installation (GPU)](https://docs.vllm.ai/en/latest/getting_started/installation/gpu.html) и поставьте совместимую связку **`torch` + `vllm`** явными версиями. На драйвере **595.x** в **`nvidia-smi`** часто видно **CUDA 13.2** — ориентируйтесь на таблицу для этой линии, а не на старые примеры с **CUDA 12.4**.

После успешного ручного **`vllm serve`** остановите (**Ctrl+C**) и оформите **§12.3** (`/etc/vllm/vllm.env`, **`systemd`**, **`systemctl enable --now vllm`**), затем **§12.4** (curl из LAN).

### 12.1. vLLM: матрица версий и окружение Python

1. На **хосте** зафиксируйте: **`nvidia-smi`** → версия драйвера и строка **CUDA Version** (для актуальных веток драйвера, например **595.x**, там часто **CUDA 13.x** — это ориентир для выбора wheel **PyTorch/vLLM**, а не обязательно «установленный CUDA toolkit» на хосте).
2. Откройте актуальную страницу установки vLLM: [vLLM installation (GPU)](https://docs.vllm.ai/en/latest/getting_started/installation/gpu.html) и таблицу совместимости **PyTorch / CUDA / vLLM** на момент установки.
3. В CT установите **Python 3.10+** (лучше **3.11** или **3.12**, если пакеты vLLM уже поддерживают), **`python3-venv`**, **`build-essential`** (иногда нужен для зависимостей), **`git`** при необходимости.

Создание venv (пример путь):

```bash
python3 -m venv /opt/vllm-venv
/opt/vllm-venv/bin/pip install -U pip wheel
```

Установка **vLLM** (команда зависит от релиза; сверяйте с документацией):

```bash
/opt/vllm-venv/bin/pip install vllm
```

Если `pip` тянет **CUDA wheel**, который **новее**, чем поддерживает драйвер на хосте, откатитесь на **явно указанные** версии `torch`/`vllm` из таблицы совместимости документации или используйте **контейнерный** образ vLLM как альтернативу (в LXC с Docker это отдельная настройка; базовый план — **venv + pip**).

### 12.1.5. Каталоги на `/srv/llm`, переменные Hugging Face и тестовая модель **Qwen/Qwen2-0.5B-Instruct**

Выполняйте **в CT** под **root**, после **`pip install vllm`** (§12.1). Нужен **интернет** в CT (у вас есть).

#### Зачем два места на диске

| Путь | Назначение |
|------|------------|
| **`/srv/llm/models/`** | **Явные копии весов** под конкретную модель: в **`vllm serve`** указываете **путь к каталогу** (`/srv/llm/models/Qwen2-0.5B-Instruct`). Удобно для «это моя установленная модель», бэкапов и офлайн без повторных скачиваний. |
| **`/srv/llm/hf/`** | **Корень кэша Hugging Face** (`HF_HOME`): сюда попадают файлы при **`hf download`** без `--local-dir`, при первом **`vllm serve <HF-id>`** и при работе библиотек **transformers**. |

Оба каталога лежат на томе **`mp0` → `/srv/llm`** (§11.2), не на маленьком rootfs.

#### Шаг 1. Создать структуру каталогов

```bash
mkdir -p /srv/llm/models /srv/llm/hf/hub
chmod 755 /srv/llm /srv/llm/models /srv/llm/hf
```

#### Шаг 2. Постоянные переменные окружения (не только на один сеанс)

**Для интерактивной работы** (SSH в CT, ручной `vllm serve`):

```bash
cat >/etc/profile.d/vllm-hf.sh <<'EOF'
# Hugging Face / vLLM — данные на /srv/llm (том mp0)
export HF_HOME=/srv/llm/hf
export HF_HUB_CACHE=/srv/llm/hf/hub
export TRANSFORMERS_CACHE=/srv/llm/hf/hub
export HF_DATASETS_CACHE=/srv/llm/hf/datasets
EOF
chmod 644 /etc/profile.d/vllm-hf.sh
```

Подхватить **в текущей** сессии без перелогина:

```bash
source /etc/profile.d/vllm-hf.sh
echo "HF_HOME=$HF_HOME"
```

**Для systemd** (сервис vLLM в §12.3) те же значения продублируйте в **`/etc/vllm/vllm.env`** (см. ниже) — unit читает **`EnvironmentFile`**, а не **`/etc/profile.d`**.

#### Шаг 3. Утилита скачивания в том же venv

```bash
/opt/vllm-venv/bin/pip install -U huggingface_hub
```

Старый **`huggingface-cli`** в новых версиях **не работает** (deprecated). Используйте команду **`hf`** из того же venv (ставится пакетом **`huggingface_hub`**).

Проверка:

```bash
/opt/vllm-venv/bin/hf --help
```

Для **закрытых** моделей на Hugging Face понадобится токен: **`/opt/vllm-venv/bin/hf auth login`** или **`export HF_TOKEN=...`** (для **Qwen2-0.5B-Instruct** обычно **не нужен**).

#### Шаг 4. Скачать **Qwen/Qwen2-0.5B-Instruct** в `/srv/llm/models/`

Рекомендуемый способ для теста — **полная копия в `models/`** (явный путь для vLLM):

```bash
source /etc/profile.d/vllm-hf.sh

/opt/vllm-venv/bin/hf download Qwen/Qwen2-0.5B-Instruct \
  --local-dir /srv/llm/models/Qwen2-0.5B-Instruct
```

Если **`hf`** ругается на неизвестный флаг — посмотрите **`hf download --help`**; в части версий вместо **`--local-dir`** используют вывод в текущий каталог и перенос вручную, либо скачивание через Python:

```bash
/opt/vllm-venv/bin/python -c "
from huggingface_hub import snapshot_download
snapshot_download('Qwen/Qwen2-0.5B-Instruct', local_dir='/srv/llm/models/Qwen2-0.5B-Instruct')
"
```

Проверка, что файлы на месте (должны быть **`config.json`**, веса **`*.safetensors`** или **`*.bin`**, токенайзер):

```bash
ls -lah /srv/llm/models/Qwen2-0.5B-Instruct/ | head -20
du -sh /srv/llm/models/Qwen2-0.5B-Instruct
```

Ожидаемый размер порядка **~1 GB** (зависит от ревизии на Hub).

**Альтернатива** (без отдельной папки в `models/`): только кэш под **`HF_HOME`**, запуск по id — файлы окажутся в **`/srv/llm/hf/hub/`**:

```bash
# не обязательно, если уже сделали download --local-dir выше
/opt/vllm-venv/bin/vllm serve Qwen/Qwen2-0.5B-Instruct ...
```

Для **постоянного** сервиса удобнее **один явный путь** в **`models/`**, как в шаге 4.

#### Шаг 5. Постоянный `/etc/vllm/vllm.env` (создаём до §12.3, **не удаляем** после)

```bash
mkdir -p /etc/vllm
cat >/etc/vllm/vllm.env <<'EOF'
# Не используйте префикс VLLM_ для своих переменных — vLLM 0.20+ ругается (Unknown vLLM environment variable).
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8000
MODEL_PATH=/srv/llm/models/Qwen3-8B-AWQ
# Справочно (для роутера / второго инстанса — не одновременно на одной 3060):
# MODEL_PATH_MEDIUM=/srv/llm/models/Qwen3-8B-AWQ
# MODEL_PATH_SMALL=/srv/llm/models/Qwen3-1.7B
# MODEL_PATH_FALLBACK=/srv/llm/models/Qwen2.5-7B-Instruct-AWQ
# MODEL_PATH_TINY=/srv/llm/models/Qwen3-0.6B
HF_HOME=/srv/llm/hf
HF_HUB_CACHE=/srv/llm/hf/hub
TRANSFORMERS_CACHE=/srv/llm/hf/hub
HF_DATASETS_CACHE=/srv/llm/hf/datasets
EOF
chmod 640 /etc/vllm/vllm.env
```

Перед **`systemctl`** можно подгружать вручную:

```bash
set -a
source /etc/vllm/vllm.env
set +a
```

#### Шаг 6. Первый тестовый запуск **vLLM** (в foreground)

Убедитесь, что GPU свободна: **`nvidia-smi`**.

```bash
source /etc/profile.d/vllm-hf.sh
# или: set -a && source /etc/vllm/vllm.env && set +a

/opt/vllm-venv/bin/vllm serve "${MODEL_PATH:-/srv/llm/models/Qwen2-0.5B-Instruct}" \
  --host 0.0.0.0 \
  --port 8000 \
  --max-model-len 4096 \
  --gpu-memory-utilization 0.90 \
  --max-num-seqs 4
```

Дождитесь строки вроде **«Uvicorn running»** / **«Application startup complete»**. Остановка теста: **Ctrl+C**.

С другого ПК в LAN (подставьте IP CT, например **`10.x.x.101`**):

```bash
curl -sS http://10.x.x.101:8000/v1/models | head
curl -sS http://10.x.x.101:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"Qwen2-0.5B-Instruct","messages":[{"role":"user","content":"ping"}],"max_tokens":32}'
```

Идентификатор в поле **`model`** смотрите в ответе **`/v1/models`** — иногда это **имя каталога** или **полный HF id**.

После успешного теста переходите к **§12.3**: unit **`vllm.service`** подключает **тот же** **`/etc/vllm/vllm.env`** через **`EnvironmentFile=`** — файл **не пересоздаём**, только при необходимости правим **`MODEL_PATH`** / HF‑переменные.

#### Краткая шпаргалка по переменным

- **`HF_HOME`** — корень всего кэша Hugging Face на диске **`/srv/llm/hf`**.
- **`HF_HUB_CACHE`** / **`TRANSFORMERS_CACHE`** — куда складываются снимки с Hub (обычно **`.../hf/hub`**); задайте **одинаково**, чтобы не плодить два кэша.
- **`HF_DATASETS_CACHE`** — только если позже тянете датасеты с Hub; для чистого инференса можно не трогать.
- Переменные **не задаются сами** при установке vLLM — только **`/etc/profile.d`** + **`vllm.env`** (и **`EnvironmentFile`** в systemd).

### 12.2. Локальные веса (боевые модели и параметры `vllm serve`)

После теста с **Qwen** (§12.1.5) большие модели кладите так же в **`/srv/llm/models/<имя>/`**, обновляйте **`MODEL_PATH`** в **`/etc/vllm/vllm.env`**, **`systemctl restart vllm`**.

**Скачивание (в CT, после `source /etc/vllm/vllm.env` и `/etc/profile.d/vllm-hf.sh`):**

```bash
/opt/vllm-venv/bin/hf download Qwen/Qwen3-8B-AWQ --local-dir /srv/llm/models/Qwen3-8B-AWQ
/opt/vllm-venv/bin/hf download Qwen/Qwen2.5-7B-Instruct-AWQ --local-dir /srv/llm/models/Qwen2.5-7B-Instruct-AWQ
/opt/vllm-venv/bin/hf download Qwen/Qwen3-1.7B --local-dir /srv/llm/models/Qwen3-1.7B
/opt/vllm-venv/bin/hf download Qwen/Qwen3-0.6B --local-dir /srv/llm/models/Qwen3-0.6B
```

Команда **`hf`** в PATH часто только из venv: **`/opt/vllm-venv/bin/hf`**.

Запуск сервера (боевой профиль под **3060 12GB**, см. замеры §12.2a):

```bash
/opt/vllm-venv/bin/vllm serve /srv/llm/models/Qwen3-8B-AWQ \
  --host 0.0.0.0 \
  --port 8000 \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.90 \
  --max-num-seqs 5
```

Смысл ключей под **RTX 3060 12GB** и **2–5** параллельных клиентов:

- **`--max-model-len`**: уменьшайте, если не хватает VRAM (типичный рычаг первым).
- **`--gpu-memory-utilization`**: при **0.90** vLLM резервирует **~90%** карты; **`nvidia-smi`** почти не меняется между маленькой и большой моделью — сравнивайте строки **`Model loading took`** и **`Available KV cache memory`** в journal.
- **`--max-num-seqs`**: ограничение числа одновременных последовательностей; для «до пяти клиентов» разумно начать с **5** и смотреть на OOM/latency.

Дополнительно при необходимости (см. `vllm serve --help` для вашей версии): **`--max-num-batched-tokens`**, **`--enforce-eager`** для отладки, **`--generation-config vllm`** если не хотите дефолты из `generation_config.json` модели.

**Смена модели:** правка **`MODEL_PATH`** в **`/etc/vllm/vllm.env`** → **`systemctl restart vllm.service`**. В **`curl`** поле **`model`** — путь как в **`MODEL_PATH`** или id из **`/v1/models`**.

### 12.2a. Замеры VRAM на RTX 3060 12GB (vLLM 0.20.2, CT 101)

Зафиксировано на узле **guests-vllm-ct** (май 2026). Общие флаги **`vllm.service`**:

`--max-model-len 8192 --gpu-memory-utilization 0.90 --max-num-seqs 5`

| Модель (каталог) | Веса на GPU (лог) | KV cache (лог) | nvidia-smi | Gen throughput (пик, лог) |
|------------------|-------------------|----------------|------------|---------------------------|
| **Qwen3-8B-AWQ** | 5.71 GiB | 3.47 GiB | 9727 / 12288 MiB | ~55–57 tok/s |
| **Qwen2.5-7B-Instruct-AWQ** | 5.20 GiB | 4.12 GiB | 9987 / 12288 MiB | ~50 tok/s |
| **Qwen3-1.7B** | 3.22 GiB | 6.54 GiB | 10449 / 12288 MiB | ~82 tok/s |
| **Qwen3-0.6B** | 1.12 GiB | 8.93 GiB | 10687 / 12288 MiB | ~54 tok/s |

**Как читать:** при **`gpu-memory-utilization=0.90`** **`nvidia-smi`** ~9.7–10.7 GiB у всех моделей — это **резерв пула**, не «размер весов». Узкое место при нескольких длинных запросах — **KV** (см. **Available KV cache memory**).

**Роли (роутинг / LLM):**

| Роль | Рекомендация | HF id |
|------|--------------|-------|
| **Локальная «средняя»** (основной vLLM) | **Qwen3-8B-AWQ** | `Qwen/Qwen3-8B-AWQ` |
| Запасная «средняя» | Qwen2.5-7B-Instruct-AWQ (чуть больше KV) | `Qwen/Qwen2.5-7B-Instruct-AWQ` |
| Локальная «маленькая» (классификатор / быстрые ответы) | Qwen3-1.7B или Qwen3-0.6B | `Qwen/Qwen3-1.7B`, `Qwen/Qwen3-0.6B` |
| Тестовая (историческая) | Qwen2-0.5B-Instruct | `Qwen/Qwen2-0.5B-Instruct` |

**Не планировать:** два **`vllm serve`** с **8B + 1.7B** одновременно на одной **3060** при **`util=0.90`**. Роутер — отдельный процесс, внешний API или **переключение** `MODEL_PATH` + restart. **Speculative decoding** (8B + 0.6B draft) — только отдельный эксперимент; по весам ~6.8 GiB только моделей, запас мал.

**Qwen3 и «thinking»:** в ответах API может появляться блок рассуждений в chat template. Для обычного чата позже настроить отключение (флаги vLLM / шаблон / `generation_config`).

**Замер на CT:**

```bash
systemctl restart vllm.service
journalctl -u vllm.service -f   # Model loading took … ; Available KV cache memory …
nvidia-smi
curl -sS http://127.0.0.1:8000/v1/models
```

В LXC блок **Processes** в **`nvidia-smi`** может быть пустым при ненулевом **Memory-Usage** — ориентир: MiB + лог vLLM.

### 12.2b. Бенчмарк serving: **Qwen3-8B-AWQ** (`vllm bench serve`)

Замер **скорости и латентности** уже поднятого **`vllm.service`** (не «качества ответов»). Инструмент встроен в venv: **`/opt/vllm-venv/bin/vllm bench serve`**. Документация: [Benchmark CLI (vLLM)](https://docs.vllm.ai/en/stable/benchmarking/cli/).

**Перед прогоном:**

```bash
systemctl is-active vllm.service   # active
curl -sS http://127.0.0.1:8000/v1/models | jq   # id для --model
mkdir -p /srv/llm/benchmarks
```

Идентификатор **`--model`** обычно совпадает с **`MODEL_PATH`** (`/srv/llm/models/Qwen3-8B-AWQ`).

**Каталог результатов:** `/srv/llm/benchmarks/` (на shared ZFS, рядом с моделями). Флаги **`--save-result`** / **`--save-detailed`** пишут JSON/отчёт (путь смотрите в выводе; при **`--result-dir`** — явно).

#### Smoke (синтетика, без датасета)

```bash
RESULT_DIR=/srv/llm/benchmarks/$(date +%Y%m%d-%H%M)-qwen3-8b-awq-smoke
mkdir -p "$RESULT_DIR"

/opt/vllm-venv/bin/vllm bench serve \
  --backend openai-chat \
  --host 127.0.0.1 \
  --port 8000 \
  --endpoint /v1/chat/completions \
  --model /srv/llm/models/Qwen3-8B-AWQ \
  --dataset-name random \
  --random-input-len 512 \
  --random-output-len 128 \
  --num-prompts 20 \
  --max-concurrency 1 \
  --save-result \
  --result-dir "$RESULT_DIR"
```

#### Нагрузка «2–5 клиентов» (ближе к `max-num-seqs 5`)

```bash
RESULT_DIR=/srv/llm/benchmarks/$(date +%Y%m%d-%H%M)-qwen3-8b-awq-load5
mkdir -p "$RESULT_DIR"

/opt/vllm-venv/bin/vllm bench serve \
  --backend openai-chat \
  --host 127.0.0.1 \
  --port 8000 \
  --endpoint /v1/chat/completions \
  --model /srv/llm/models/Qwen3-8B-AWQ \
  --dataset-name random \
  --random-input-len 1024 \
  --random-output-len 256 \
  --num-prompts 50 \
  --max-concurrency 5 \
  --request-rate 2 \
  --save-result \
  --save-detailed \
  --result-dir "$RESULT_DIR"
```

#### С ноутбука в LAN

Тот же вызов, но **`--host 10.x.x.101`** (IP CT **101**) вместо **`127.0.0.1`**.

#### Что смотреть в итоговой сводке

| Метрика | Смысл |
|---------|--------|
| **Output token throughput (tok/s)** | Скорость генерации |
| **Request throughput (req/s)** | Запросов в секунду |
| **Mean / P99 TTFT** | Время до первого токена |
| **Mean / P99 TPOT** | Время на выходной токен (после первого) |

Параллельно: **`journalctl -u vllm.service -f`** (KV cache %), **`nvidia-smi`**, при необходимости **`curl http://127.0.0.1:8000/metrics`**.

**Qwen3:** в ответах может быть блок рассуждений (thinking) — для сопоставимости прогонов держите одинаковые **`random-output-len`** / **`max_tokens`**; при сравнении с Qwen2.5 учитывайте лишние токены.

**Скрипт в репозитории:** `scripts/ct/bench-vllm-serve.sh` (`smoke` | `load`).

**Другие режимы:** **`vllm bench throughput`** / **`vllm bench latency`** — отдельный прогон без API; для «как в проде» достаточно **`bench serve`**. Отчёты погружнее: [GuideLLM](https://github.com/vllm-project/guidellm).

### 12.3. systemd в CT

1. Пользователь для сервиса: можно **`root`** на домашнем сервере или отдельный **`vllm`** с правами на каталог моделей и venv.
2. Файл **`/etc/vllm/vllm.env`** — если уже создан в **§12.1.5**, **оставьте его** и только проверьте содержимое. Это **основной конфиг** и для **systemd**, и для ручной отладки (`set -a && source /etc/vllm/vllm.env && set +a`). Удалять после настройки сервиса **не нужно**.

Если файла ещё нет — создайте (права **`640`** / **`600`**, если внутри секреты):

```bash
mkdir -p /etc/vllm
```

Пример **`/etc/vllm/vllm.env`** (боевой **medium**, см. §12.2a):

```
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8000
MODEL_PATH=/srv/llm/models/Qwen3-8B-AWQ
MODEL_PATH_MEDIUM=/srv/llm/models/Qwen3-8B-AWQ
MODEL_PATH_SMALL=/srv/llm/models/Qwen3-1.7B
MODEL_PATH_FALLBACK=/srv/llm/models/Qwen2.5-7B-Instruct-AWQ
MODEL_PATH_TINY=/srv/llm/models/Qwen3-0.6B
HF_HOME=/srv/llm/hf
HF_HUB_CACHE=/srv/llm/hf/hub
TRANSFORMERS_CACHE=/srv/llm/hf/hub
HF_DATASETS_CACHE=/srv/llm/hf/datasets
```

**`MODEL_PATH_*`** — справочно для скриптов роутера; активная модель — только **`MODEL_PATH`**. Не задавайте **`VLLM_HOST`** / **`VLLM_PORT`**: vLLM воспринимает **`VLLM_*`** как свои env и пишет warning. Шаблон в репо: **`scripts/ct/vllm.env.example`**.

**Миграция с CT, где уже есть `VLLM_HOST`:** в **`/etc/vllm/vllm.env`** переименовать в **`LISTEN_HOST`** / **`LISTEN_PORT`**; в **`/etc/systemd/system/vllm.service`** в **`ExecStart`** — **`${LISTEN_HOST}`** / **`${LISTEN_PORT}`**; затем **`systemctl daemon-reload && systemctl restart vllm`**.

3. Unit **`/etc/systemd/system/vllm.service`** (флаги инференса продублированы в **`ExecStart`**, чтобы systemd корректно передал каждый аргумент; при изменении — правьте строку целиком):

```ini
[Unit]
Description=vLLM OpenAI-compatible server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/vllm/vllm.env
ExecStart=/opt/vllm-venv/bin/vllm serve ${MODEL_PATH} --host ${LISTEN_HOST} --port ${LISTEN_PORT} --max-model-len 8192 --gpu-memory-utilization 0.90 --max-num-seqs 5
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now vllm.service
journalctl -u vllm.service -f
```

### 12.4. Проверки из LAN

С другого ПК в той же сети (подставьте IP CT):

```bash
curl -sS http://<IP_CT>:8000/v1/models | head
curl -sS http://<IP_CT>:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"/srv/llm/models/Qwen3-8B-AWQ","messages":[{"role":"user","content":"ping"}],"max_tokens":16}'
```

В поле **`model`** укажите тот идентификатор, который ожидает ваш запуск (часто это **путь** или **HuggingFace id** — смотрите вывод **`/v1/models`**).

**Безопасность**: по умолчанию слушать только **LAN**; при необходимости ограничьте **`pve-firewall`** / роутером доступ к **`<IP_CT>:8000`**.

### 12.5. Несколько моделей на 12 GB VRAM и роутинг

Одновременно держать **две загруженные** модели в VRAM на **3060 12GB** при **`gpu-memory-utilization=0.90`** **нельзя** (см. замеры §12.2a: один процесс уже занимает ~9.7–10.7 GiB в **`nvidia-smi`**).

**Зафиксированные пути на диске** (`/srv/llm/models/`):

| Переменная (справочно) | Каталог | Роль |
|------------------------|---------|------|
| **`MODEL_PATH`** / **`MODEL_PATH_MEDIUM`** | `Qwen3-8B-AWQ` | Локальная **«средняя»** — основной **`vllm.service`** |
| **`MODEL_PATH_FALLBACK`** | `Qwen2.5-7B-Instruct-AWQ` | Запасная «средняя» |
| **`MODEL_PATH_SMALL`** | `Qwen3-1.7B` | Локальная «маленькая» (роутер / классификатор) |
| **`MODEL_PATH_TINY`** | `Qwen3-0.6B` | Минимальный footprint |

Рабочие схемы:

1. **Один vLLM, одна модель** — продакшен: **`MODEL_PATH=Qwen3-8B-AWQ`**. Смена: правка env + **`systemctl restart vllm`**.
2. **Роутер (Python / LiteLLM / внешний cheap API)** — решает `local_medium` | `external_large` | …; исполнение — **один** вызов к **`http://<CT>:8000/v1`** с **`model`** = путь medium или отдельный HTTP к облаку. Локальная **1.7B** как роутер — только **второй инстанс на другом порту** или **не на GPU одновременно** с 8B.
3. **Два unit’а на 8000/8001** — только **взаимоисключение** (`Conflicts=` в systemd или GPU mutex на уровне PVE, §11.2a).
4. **Speculative decoding** (8B + 0.6B draft) — отдельный эксперимент, не смешивать с «два serve».

Пример с **OpenAI SDK** (medium на CT **101**):

```python
from openai import OpenAI

MEDIUM = "/srv/llm/models/Qwen3-8B-AWQ"
client = OpenAI(base_url="http://10.x.x.101:8000/v1", api_key="unused")
client.chat.completions.create(
    model=MEDIUM,
    messages=[{"role": "user", "content": "hi"}],
)
```

Для «настоящей» мульти‑модели в **одном** процессе vLLM — LoRA / speculative / MTP по доке вашей версии vLLM; на **12 GB** для двух полноразмерных чекпоинтов это не целевой сценарий.

### 12.6. Игры (Steam) в VM на Proxmox — отдельная ветка
- Требуется **PCI passthrough** всей **RTX 3060** в VM (Windows или Linux).
- **RX 550** остаётся для **консоли Proxmox** (переведите монитор на неё при отладке VFIO).
- Пока 3060 захвачена VM, **не** используйте её для LLM на хосте/LXC.

Кратко по этапам VFIO: группы IOMMU, `vfio-pci`, OVMF/UEFI для гостя, отключение конфликтующих драйверов на хосте для 3060 — **отдельная пошаговая сессия**, чтобы не ломать рабочий LLM.

---

## Быстрые проверки/типовые проблемы

### Проблема: веб‑панель не открывается
Проверьте по порядку:
- сервер точно получил **`10.x.x.225`**?
- кабель Ethernet воткнут и линк есть?
- ваш ПК в той же подсети `10.x.x.0/24`?
- пробуете именно `https://...:8006`?

### Проблема: IP “уехал” и стал другим
Решение:
- либо настроить **DHCP reservation** на роутере,
- либо прописать статику на Proxmox на `vmbr0`.

### Проблема: ВМ не получает IP в домашней сети
Проверьте:
- ВМ подключена к **`vmbr0`**.
- У `vmbr0` есть **bridge ports = Ethernet интерфейс**.
- Ваша домашняя сеть раздаёт DHCP.

### Проблема: `apt update` ругается на `pve-enterprise` / отсутствует подписка
- Выполните **раздел 4.0** (отключить enterprise, добавить **`pve-no-subscription`**), затем снова `apt update`.

### Проблема: не заходит SSH на 1234
Проверьте:
- `sshd_config`: `Port 1234` и `systemctl restart ssh`.
- Вы точно указываете `-p 1234`.
- На первое время можно оставить порт 22 как запасной.

### Проблема: `nvidia-smi` не находится / на 3060 висит `nouveau`
- На чистой системе без проприетарного драйвера — **норма**. Нужна установка **NVIDIA proprietary** на хост PVE.
- После установки должен исчезнуть **`Kernel driver in use: nouveau`** для 3060 (заменится на **`nvidia`**).

### Проблема: amdgpu «Cannot find any crtc» в `dmesg`
- Обычно означает **нет подключённого монитора к RX 550**. Если экран на 3060 — можно игнорировать.
- Для проверки RX 550 временно подключите монитор к её выходу.

### Проблема: нужны и LLM на хосте, и игра в VM на одной 3060 одновременно
- **Так нельзя**: одна карта либо под **VFIO‑VM**, либо под **NVIDIA на хосте**. Варианты: LLM внутри той же VM, разные профили загрузки, или отказ от passthrough для игр.

### Проблема: в LXC `nvidia-smi` → Failed to initialize NVML / нет устройств
- Проверьте **`lxc.mount.entry`** и **`lxc.cgroup2.devices.allow`** по фактическим **`ls -l /dev/nvidia*`** на **хосте** (majors могут отличаться от примера в **§11.4**).
- Убедитесь, что CT **privileged** и после правок конфига был **`pct stop` / `pct start`**.
- Сверьте **user-space** библиотеки в CT с версией драйвера на хосте (**§11.5**).

### Проблема: vLLM не стартует (CUDA driver / unsupported GPU / OOM)
- Сверьте **драйвер хоста** и **CUDA в wheel PyTorch** с таблицей на [странице установки vLLM](https://docs.vllm.ai/en/latest/getting_started/installation/gpu.html).
- Уменьшите **`--max-model-len`**, **`--gpu-memory-utilization`**, **`--max-num-seqs`**; смотрите **`journalctl -u vllm`** и **`nvidia-smi`** во время запуска.

