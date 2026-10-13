#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]   $desc"
        ((PASS++))
    else
        echo " [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++))
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"

check "Вход от имени root запрещён" \
    "no" \
    "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"

check "Парольная аутентификация отключена" \
    "no" \
    "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

PORT="$(sudo sshd -T | awk '/^port/{print $2; exit}')"
if [[ "$PORT" != "22" ]]; then
    echo " [OK]   SSH использует нестандартный порт ($PORT)"
    ((PASS++))
else
    echo " [FAIL] SSH использует стандартный порт 22"
    ((FAIL++))
fi

check "MaxAuthTries равен 3" \
    "3" \
    "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"

check "Межсетевой экран активен" \
    "active" \
    "$(sudo ufw status | awk '/^Status:/{print $2}')"

check "Политика входящего трафика" \
    "deny" \
    "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"

awk -F: '$3>=1000 && $3<65534 {printf "              %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"

check "Служба nginx активна" \
    "active" \
    "$(systemctl is-active nginx 2>/dev/null)"

if sudo nginx -t >/dev/null 2>&1; then
    nginx_config="ok"
else
    nginx_config="error"
fi
check "Конфигурация nginx корректна" "ok" "$nginx_config"

# Для проверки отрицательного сценария порог можно временно увеличить.
CERT_MIN_SECONDS="${AUDIT_CERT_MIN_SECONDS:-2592000}"
if openssl x509 -in /etc/ssl/certs/devops.crt \
    -checkend "$CERT_MIN_SECONDS" -noout >/dev/null 2>&1; then
    cert_status="valid"
else
    cert_status="invalid"
fi
check "Сертификат действует ещё не менее 30 дней" "valid" "$cert_status"

if writable_path="$(find /var/www/devops-site -perm -o+w -print -quit 2>/dev/null)" \
    && [[ -z "$writable_path" ]] \
    && [[ "$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null)" == "600" ]]; then
    permissions_status="secure"
else
    permissions_status="insecure"
fi
check "Нет записи для всех; права ключа 600" "secure" "$permissions_status"

echo "Пройдено: $PASS, не пройдено: $FAIL"

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
