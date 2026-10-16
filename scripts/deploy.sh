#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# --- 1. Разбор аргумента --dry-run ---
DRY_RUN=0
case "${1:-}" in
  "")          DRY_RUN=0 ;;
  --dry-run)   DRY_RUN=1 ;;
  *)
    echo "Использование: $0 [--dry-run]" >&2
    exit 1
    ;;
esac

# --- 2. Проверки по требованиям 4 и 5 ---

# Требование 4: site/index.html должен существовать
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
  echo "Ошибка: файл ${LOCAL_DIR}index.html не найден — доставка отменена" >&2
  exit 1
fi

# Требование 5: в репозитории не должно быть незафиксированных изменений
if [[ -n "$(git status --porcelain)" ]]; then
  echo "Ошибка: в репозитории есть незафиксированные изменения — доставка отменена" >&2
  git status --short >&2
  exit 1
fi

# Короткий хеш доставленного коммита (для требования 7)
COMMIT_HASH="$(git rev-parse --short HEAD)"

# --- 3. Синхронизация каталога ---
# Требование 9: не запрашивать пароль — BatchMode=yes, ConnectTimeout
SSH_OPTS="ssh -o BatchMode=yes -o ConnectTimeout=5"

RSYNC_ARGS=(
  -avz
  --delete
  --chmod=D755,F644
  -e "${SSH_OPTS}"
)
if [[ "${DRY_RUN}" -eq 1 ]]; then
  RSYNC_ARGS+=(--dry-run)
fi

echo "==> Синхронизация ${LOCAL_DIR} -> ${REMOTE}:${REMOTE_DIR}"
rsync "${RSYNC_ARGS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# --- 4. При --dry-run — завершение без проверки доступности ---
if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "==> Режим --dry-run: проверка доступности не выполняется"
  exit 0
fi

# --- 5. Проверка доступности ресурса с проверкой сертификата ---
# Требование 6: curl -f, --cacert, без -k
echo "==> Проверка доступности ${SITE_URL}"
if ! curl -fsS --cacert "${CA_CERT}" "${SITE_URL}" > /dev/null; then
  echo "Ошибка: ресурс ${SITE_URL} недоступен" >&2
  exit 1
fi

# --- Требование 7: успех, код 0, короткий хеш ---
echo "==> Доставка выполнена успешно. Коммит: ${COMMIT_HASH}"
exit 0