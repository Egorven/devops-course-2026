# Конфигурация виртуальной машины devops-vm

> Документ описывает конфигурацию ВМ `devops-vm` и используется как
> исходные данные при разработке Ansible-роли (практика № 11)
> и для восстановления после отката на снимок `01-clean-install` (практика № 6).

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Hypervisor | VirtualBox |
| ОС | Ubuntu 26.04.1 LTS (64-bit) |
| Имя ВМ | devops-vm |
| ОЗУ | 2048 МБ (выделено ВМ); доступно в ОС ≈ 1.6 ГиБ |
| Ядер CPU | 2 |
| Диск (VDI) | 25 ГБ, динамический |
| Корневой раздел (/) | 12 ГБ (LVM) |
| Swap | 2.0 ГиБ |
| Видеопамять | 16 МБ (VMSVGA) |
| FQDN | devops-vm.devops.local |

## 2. Сетевые интерфейсы

| Интерфейс | Тип адаптера | Модель | IP-адрес | Назначение |
|---|---|---|---|---|
| enp0s3 | NAT | Intel PRO/1000 MT Desktop | 10.0.2.15/24 (DHCP) | выход в интернет |
| enp0s8 | Host-only | Intel PRO/1000 MT Desktop | 192.168.56.101/24 | доступ с хоста |

- Шлюз по умолчанию: `10.0.2.2`
- Шлюз host-only: `192.168.56.1`
- На хосте в `C:\Windows\System32\drivers\etc\hosts`:
  ```
  192.168.56.101   devops.local
  ```

## 3. Правило проброса портов


| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя | Назначение |
|---|---|---|---|---|---|---|
| ssh | TCP | 127.0.0.1 | 2222 | (все) | 2222 | SSH-доступ с хоста |

## 4. Учётные записи

| Имя | UID | Группы | Аутентификация |
|---|---|---|---|
| student | 1000 | student, adm, cdrom, sudo, dip, plugdev, users, lxd | пароль |
| devops | 1001 | devops, sudo, users | SSH-ключ `devops_vm` |
| root | 0 | root | заблокирован |

Публичный ключ `devops_vm.pub` размещён в `/home/devops/.ssh/authorized_keys`.

## 5. Служба SSH

| Параметр | Значение |
|---|---|
| Порт | 2222 |
| PermitRootLogin | no |
| PasswordAuthentication | no |
| PubkeyAuthentication | yes |
| PermitEmptyPasswords | no |
| MaxAuthTries | 3 |
| LoginGraceTime | 30 |
| AllowUsers | devops |
| X11Forwarding | no |
| ClientAliveInterval | 300 |
| ClientAliveCountMax | 2 |

Файлы конфигурации:
- `/etc/ssh/sshd_config` — основной
- `/etc/ssh/sshd_config.d/99-hardening.conf` — наши изменения

Содержимое `99-hardening.conf`:

```
Port 2222

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30

AllowUsers devops

X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

## 6. Правила межсетевого экрана

Политики по умолчанию:
```
Default: deny (incoming), allow (outgoing), disabled (routed)
```

Правила:

| # | Действие | Порт | Источник | Комментарий |
|---|---|---|---|---|
| 1 | ALLOW IN | 80/tcp | Anywhere | HTTP |
| 2 | ALLOW IN | 443/tcp | Anywhere | HTTPS |
| 3 | LIMIT IN | 2222/tcp | Anywhere | SSH rate-limited |
| 4 | ALLOW IN | 80/tcp (v6) | Anywhere (v6) | HTTP |
| 5 | ALLOW IN | 443/tcp (v6) | Anywhere (v6) | HTTPS |
| 6 | LIMIT IN | 2222/tcp (v6) | Anywhere (v6) | SSH rate-limited |

## 7. Снимки состояния

| Имя | Момент создания |
|---|---|
| 01-clean-install | 10.10.2026 14:01 |
| 02-keys-configured | 10.10.2026 14:59 |
| 03-ssh-hardened | 10.10.2026 15:40 |

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Устанавливаемый пакет | `nginx` (Ubuntu 26.04) |
| Версия | `nginx/1.28.3 (Ubuntu)` |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site` |
| Активация | симлинк `/etc/nginx/sites-enabled/devops-site` |
| Каталог ресурса | `/var/www/devops-site` |
| Владелец каталога | `root:root` |
| Права каталога | `755` (`drwxr-xr-x`) |
| Права файлов | `644` (`-rw-r--r--`) |
| Пользователь воркеров | `www-data` (только чтение) |
| Сертификат | `/etc/ssl/certs/devops.crt`, права `644`, владелец `root:root` |
| Приватный ключ | `/etc/ssl/private/devops.key`, права `600`, владелец `root:root` |
| Срок действия сертификата | 365 дней (выпущен 16.10.2026, до 16.10.2027) |
| Прослушиваемые порты | 80 (редирект на HTTPS), 443 (ssl) |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |

**Команда формирования самоподписанного сертификата:**

```bash
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -days 365 \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
```

**Содержимое конфигурации** `/etc/nginx/sites-available/devops-site` — два блока `server`:

```nginx
# Блок 1: перенаправление HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

# Блок 2: HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
```

## 9. Контейнеризация
| Параметр | Значение |
|---|---|
| **Способ установки Docker Engine** | Официальный репозиторий Docker (`download.docker.com`), пакеты `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`. Пакет `docker.io` из репозитория Ubuntu **не использовался**. |
| **Версия Docker Engine** | `27.x` (актуальная на момент установки) |
| **Участники группы `docker`** | Пользователь `devops` (добавлен командой `sudo usermod -aG docker devops`) |
| **Расположение проекта на сервере** | `/home/devops/app` (содержит `docker-compose.yml`, `Dockerfile`, исходный код) |
| **Расположение файла `.env`** | `/home/devops/app/.env` |
| **Права файла `.env`** | `600` (`-rw-------`), владелец `devops:devops` |
| **Публикуемые порты и адреса** | Приложение: `127.0.0.1:5000` (только локально); PostgreSQL: порт не публикуется (доступен только по имени сервиса внутри Docker-сети) |
| **Именованные тома** | `app_db_data` (том для хранения данных PostgreSQL) |
| **Конфигурация обратного прокси** | `location /app/` в `/etc/nginx/sites-available/devops-site`, перенаправление на `http://127.0.0.1:5000/` |

### Установка Docker Engine

```bash
sudo apt update && sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

Пользователь `devops` добавлен в группу `docker`:
```bash
sudo usermod -aG docker devops
```

### Расположение проекта и файла `.env`

Проект размещён в `/home/devops/app`. Файл `.env` (переменные окружения с паролями СУБД) защищён правами `600` (чтение/запись только для владельца `devops`), чтобы предотвратить утечку секретов.

### Публикуемые порты и адреса

- **Приложение:** публикуется только на `127.0.0.1:5000`, что делает его недоступным из внешней сети напрямую. Nginx обращается к нему как к upstream.
- **PostgreSQL:** порт не публикуется, доступен контейнерам внутри сети по имени сервиса (`db:5432`).

Прямая публикация на `0.0.0.0:5000` исключена, так как Docker обходит правила UFW.

### Именованные тома

Для сохранения данных PostgreSQL используется именованный том `app_db_data` (создаётся автоматически при первом `docker compose up`, сохраняется при `docker compose down`, удаляется при `down -v`).

### Конфигурация обратного прокси-сервера

В файле `/etc/nginx/sites-available/devops-site` (в блоке `listen 443 ssl`) добавлен `location /app/`:

```nginx
location /app/ {
    proxy_pass http://127.0.0.1:5000/;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```
Запросы к `https://devops.local/app/` перенаправляются на приложение в контейнере. Статический ресурс по пути `/` сохранён для сценария деплоя в ПР № 12.

---

## Приложение А. Команды восстановления после отката на `01-clean-install`

> Выполнять по порядку под пользователем с правами `sudo`.

### А.1. Пользователь devops

```bash
sudo adduser --disabled-password --gecos "" devops
sudo usermod -aG sudo,adm devops
```

### А.2. SSH-ключ

```bash
sudo -u devops mkdir -p /home/devops/.ssh
sudo -u devops chmod 700 /home/devops/.ssh
sudo -u devops tee /home/devops/.ssh/authorized_keys >/dev/null <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaiA926K2283GmNUITXzSTV3hAR7sOxNA5w4ZEjgYHa devops-vm-key
EOF
sudo -u devops chmod 600 /home/devops/.ssh/authorized_keys
```

### А.3. SSH-hardening

```bash
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf >/dev/null <<'EOF'
Port 2222

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30

AllowUsers devops

X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

sudo sshd -t && sudo systemctl restart ssh
```

### А.4. UFW

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw --force enable
```

### А.5. Hostname и FQDN

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127\.0\.1\.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f   # → devops-vm.devops.local
```

### А.6. Веб-сервер nginx

```bash
# Установка
sudo apt update && sudo apt install -y nginx

# Каталог ресурса
sudo mkdir -p /var/www/devops-site
sudo tee /var/www/devops-site/index.html >/dev/null <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8"><title>DevOps Course 2026</title></head>
<body>
  <h1>DevOps Course 2026</h1>
  <p>Студент: Сидоров Егор Деничович, группа ЭФБО-10-24</p>
  <p>Содержимое доставлено средствами rsync.</p>
</body>
</html>
EOF
sudo tee /var/www/devops-site/404.html >/dev/null <<'EOF'
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="UTF-8"><title>404 — не найдено</title></head>
<body><h1>404 — страница не найдена</h1></body>
</html>
EOF
sudo chown -R root:root /var/www/devops-site
sudo chmod 755 /var/www/devops-site
sudo chmod 644 /var/www/devops-site/*.html

# Конфигурация ресурса
sudo tee /etc/nginx/sites-available/devops-site >/dev/null <<'EOF'
# Блок 1: перенаправление HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

# Блок 2: HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
EOF

# Активация
sudo ln -sf /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/devops-site
sudo rm -f /etc/nginx/sites-enabled/default

# Сертификат
sudo openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -days 365 \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"

sudo chown root:root /etc/ssl/private/devops.key /etc/ssl/certs/devops.crt
sudo chmod 600 /etc/ssl/private/devops.key
sudo chmod 644 /etc/ssl/certs/devops.crt

# Проверка и запуск
sudo nginx -t && sudo systemctl reload nginx
```

### А.7. Установка Docker Engine и запуск приложения

```bash
# Установка Docker Engine (официальный репозиторий)
sudo apt update && sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Добавление пользователя devops в группу docker
sudo usermod -aG docker devops

# Восстановление проекта и конфигурации
mkdir -p /home/devops/app
# (здесь подразумевается, что файлы проекта скопированы из резервной копии 
# или репозитория, как описано в шагах выше)

# Создание файла .env и настройка прав
cd /home/devops/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env

# Запуск контейнеров
docker compose down -v  # удаление старых томов (если есть)
docker compose up -d
```

### А.8. Проверка

```bash
cd ~
sudo ./audit.sh; echo "Код возврата: $?"

# Ожидается: Пройдено: 15, не пройдено: 0; код возврата 0

# Проверка nginx
sudo ss -tlnp | grep nginx        # порты 80 и 443
curl -k https://devops.local/     # содержимое index.html

# Проверка docker
docker ps
curl -s http://127.0.0.1:5000/
```