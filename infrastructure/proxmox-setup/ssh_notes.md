# Пометки по настройке ssh-доступа

На pve-хосте (proxmox 9.1, debian 13) и в контейнере 101 (ububtu 24) мы первоначально настраивали ssh-доступ по паролю.

Установили ssh-сервер,

```
apt update
apt install -y openssh-server
systemctl enable --now ssh
```

завели пользователя guests,

```bash
adduser guests
usermod -aG sudo guests
...
mkdir -p /home/guests/.ssh
touch /home/guests/.ssh/authorized_keys
chown -R guests:guests /home/guests/.ssh
chmod 700 /home/guests/.ssh
chmod 600 /home/guests/.ssh/authorized_keys
```

поправили под себя `/etc/ssh/sshd_config`: поставили порт **1234**, на **первом этапе** разрешили заходить по паролю (чтобы сделать `ssh-copy-id`), запретили логиниться под рутом.

**Этап 1 — временно, до настройки ключей** (`/etc/ssh/sshd_config`):

```
Include /etc/ssh/sshd_config.d/*.conf

Port 1234

PermitRootLogin no

#PubkeyAuthentication yes
# Expect .ssh/authorized_keys2 to be disregarded by default in future.
#AuthorizedKeysFile	.ssh/authorized_keys .ssh/authorized_keys2

PasswordAuthentication yes
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_* COLORTERM NO_COLOR
Subsystem	sftp	/usr/lib/openssh/sftp-server
```

```bash
systemctl restart ssh
```

С портом была трабла, уже описанная в основной заметке, про включённый по-умолчанию режим `ssh.socket` в современных Linux, про то, что порт форсируется ещё в `/etc/systemd/system/ssh.socket.d/listen.conf`, и его надо поменять там:

```bash
nano /etc/systemd/system/ssh.socket.d/listen.conf
```

```
[Socket]
ListenStream=
ListenStream=0.0.0.0:1234
ListenStream=[::]:1234
```

```bash
systemctl daemon-reload
systemctl restart ssh.socket
```

А далее мы включили доступ по публичному ключу с рабочей машины (с ноутбука `Notebook`).

Как мы это делали:

На Notebook уже был создан ключ, `id_ed25519`,

мы добавили два хоста в `~/.ssh/config`:

```bash
notebook@Notebook:~$ nano ~/.ssh/config
```

```
Host *
    ServerAliveInterval 30
    ServerAliveCountMax 5
...
Host guests-pve
    HostName 10.x.x.123
    Port 1234
    User guests
    IdentityFile ~/.ssh/id_ed25519

Host guests-101
    HostName 10.x.x.101
    Port 1234
    User guests
    IdentityFile ~/.ssh/id_ed25519
...
```

И отправили ключи на те два хоста специальными командами:

```bash
notebook@Notebook:~$ ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 1234 guests@10.x.x.123
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/notebook/.ssh/id_ed25519.pub"
...
Number of key(s) added: 1
...

notebook@Notebook:~$ ssh-copy-id -i ~/.ssh/id_ed25519.pub -p 1234 guests@10.x.x.101
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/home/notebook/.ssh/id_ed25519.pub"
...
Number of key(s) added: 1
...
```

После чего ходим на удалённые сервера просто вот так:

```bash
notebook@Notebook:~$ ssh guests-pve
Linux host 6.17.13-7-pve #1 SMP PREEMPT_DYNAMIC PMX 6.17.13-7 (2026-05-08T09:58Z) x86_64
...
guests@...:~$ su -
...
root@...:~#
root@...:~# uname -a
Linux host 6.17.13-7-pve #1 SMP PREEMPT_DYNAMIC PMX 6.17.13-7 (2026-05-08T09:58Z) x86_64 GNU/Linux
root@...:~# hostname -a
...
root@...:~# hostname -I
10.x.x.123
...
```

**NB**: строки `PubkeyAuthentication` и `AuthorizedKeysFile` в примере **не раскомментировали** — в OpenSSH на Ubuntu 22.04+ / Debian 12+ ключи по умолчанию включены, даже если строки с `#`. Проверьте, что в `/etc/ssh/sshd_config.d/` нет **`PubkeyAuthentication no`**.

Для `authorized_keys`: папка **`700`**, файл **`600`** (см. блок создания пользователя выше).

### Этап 2 — боевое состояние (после `ssh-copy-id`)

На **хосте Proxmox** и в **CT 101** меняем **`PasswordAuthentication`** на **`no`**, перезапускаем SSH. То же — в [instruction.md](instruction.md) §7.4.

```
Include /etc/ssh/sshd_config.d/*.conf

Port 1234

PermitRootLogin no

PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

PasswordAuthentication no
PermitEmptyPasswords no
KbdInteractiveAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_* COLORTERM NO_COLOR
Subsystem	sftp	/usr/lib/openssh/sftp-server
```

```bash
# на каждом узле (host и CT 101), под root
nano /etc/ssh/sshd_config
sshd -t && systemctl restart ssh
# если порт задаётся через ssh.socket — listen.conf не трогаем, только sshd_config
```

Проверка с ноутбука (должен пускать по ключу, пароль не спрашивать):

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no guests@10.x.x.123 -p 1234
# ожидаем отказ, если пароль действительно выключен
ssh guests-pve
ssh guests-101
```

Повторить **`ssh-copy-id`** и этап 2 на **втором** узле, если ключи ставили по очереди.
