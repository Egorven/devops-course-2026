#!/usr/bin/env bash
set -uo pipefail

PASS=0; FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo "  [OK]   $desc"; ((PASS++))
    else
        echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён"        "no"  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no"  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1
check "Порт SSH отличен от 22" "yes" \
    "$( [[ "$(sudo sshd -T | awk '/^port/{print $2}')" != "22" ]] && echo yes || echo no )"

# TODO 2
check "MaxAuthTries равен 3" "3" \
    "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" \
    "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3
check "Политика входящего трафика — deny" "deny" \
    "$(sudo ufw status verbose | grep -oP '^Default:\s*\K\w+')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "    %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"

# а) служба nginx активна
check "Служба nginx активна" "active" \
  "$(systemctl is-active nginx)"

# б) конфигурация nginx синтаксически корректна
check "Конфигурация nginx корректна" "ok" \
  "$(sudo nginx -t >/dev/null 2>&1 && echo ok || echo fail)"

# в) сертификат истекает не ранее чем через 30 дней
check "Сертификат действителен не менее 30 дней" "ok" \
  "$(sudo openssl x509 -checkend $((30*24*3600)) -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1 && echo ok || echo fail)"

# г) нет файлов, доступных на запись всем
check "Нет файлов, доступных на запись всем" "ok" \
  "$(find /var/www/devops-site -perm -o+w | grep -q . && echo fail || echo ok)"

# г) права ключа = 600
check "Права ключа /etc/ssl/private/devops.key = 600" "600" \
  "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"


echo "[5] Контейнеризация"

# а) служба docker активна
check "Служба docker активна" "active" \
  "$(systemctl is-active docker)"

# б) контейнер СУБД находится в состоянии healthy
check "Контейнер СУБД (app-db-1) в состоянии healthy" "healthy" \
  "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'not_found')"

# в) порты 5000 и 5432 не прослушиваются ни на одном адресе, кроме 127.0.0.1
check "Порты 5000 и 5432 слушают только 127.0.0.1" "ok" \
  "$(ss -tln | grep -E ':(5000|5432)\s' | grep -vq '127.0.0.1' && echo 'fail' || echo 'ok')"

# г) права файла ~/app/.env равны 600
check "Права файла app/.env = 600" "600" \
  "$(stat -c '%a' "./app/.env" 2>/dev/null || echo 'not_found')"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1