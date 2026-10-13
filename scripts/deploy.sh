#!/usr/bin/env bash
set -euo pipefail

fail() {
    echo "Ошибка: $*" >&2
    exit 1
}

DRY_RUN=false
case "${1:-}" in
    "") ;;
    --dry-run) DRY_RUN=true ;;
    *) fail "Использование: scripts/deploy.sh [--dry-run]" ;;
esac
[[ $# -le 1 ]] || fail "Слишком много аргументов"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LOCAL_DIR="$ROOT/site/"
REMOTE="devops"
REMOTE_DIR="/var/www/devops-site/"
SITE_URL="https://devops.local"
CA_CERT="$HOME/devops.crt"

[[ -f "${LOCAL_DIR}index.html" ]] || fail "Отсутствует site/index.html"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] \
    || fail "Есть незафиксированные изменения"

if ! $DRY_RUN; then
    [[ -r "$CA_CERT" ]] || fail "Не найден сертификат $CA_CERT"
fi

OPTIONS=(-avz --delete --chmod=D755,F644)
if $DRY_RUN; then
    OPTIONS+=(--dry-run)
fi

rsync "${OPTIONS[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "$REMOTE:$REMOTE_DIR" \
    || fail "Не удалось доставить сайт"

if $DRY_RUN; then
    echo "Пробный запуск завершён: сервер не изменён"
    exit 0
fi

curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" --output /dev/null "$SITE_URL" \
    || fail "Проверка HTTPS не пройдена"

echo "Деплой успешен: $(git -C "$ROOT" rev-parse --short HEAD)"
