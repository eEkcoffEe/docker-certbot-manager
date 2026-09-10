#!/usr/bin/env bash

set -euo pipefail

CERTBOT_DIR="/opt/certbot"
COMPOSE_FILE="${CERTBOT_DIR}/docker-compose.yml"
CRON_LINE="0 0 28 * * cd ${CERTBOT_DIR} && docker compose run --rm certbot renew"

DOMAIN="${1:-}"

if [[ -z "$DOMAIN" ]]; then
    echo "Использование:"
    echo "  $0 example.duckdns.org"
    exit 1
fi

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]]; then
    echo "Ошибка: некорректное имя домена: $DOMAIN"
    exit 1
fi

echo "=============================================="
echo " SSL Certificate Setup"
echo " Домен: $DOMAIN"
echo "=============================================="

# Проверка root
if [[ "$EUID" -ne 0 ]]; then
    echo "Ошибка: скрипт необходимо запускать от root."
    exit 1
fi

# Проверка Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "Ошибка: Docker не установлен."
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    echo "Ошибка: Docker Compose plugin не установлен."
    exit 1
fi

echo "[1/7] Создание каталога Certbot..."
mkdir -p "$CERTBOT_DIR/certs"

# Создание compose
echo "[2/7] Создание docker-compose.yml..."

cat > "$COMPOSE_FILE" <<'EOF'
services:
  certbot:
    container_name: certbot
    image: certbot/certbot
    network_mode: host
    volumes:
      - ./certs:/etc/letsencrypt
EOF

cd "$CERTBOT_DIR"

# Проверка существующего сертификата
if [[ -f "${CERTBOT_DIR}/certs/live/${DOMAIN}/fullchain.pem" ]]; then
    echo
    echo "Внимание: сертификат для ${DOMAIN} уже существует."

    read -r -p "Продолжить и выполнить certbot certonly? [y/N]: " ANSWER

    if [[ ! "$ANSWER" =~ ^[Yy]$ ]]; then
        echo "Отменено."
        exit 0
    fi
fi

# Проверка порта 80
echo "[3/7] Проверка порта TCP/80..."

if ss -lnt 2>/dev/null | grep -qE '(^|[[:space:]])(0\.0\.0\.0|\[::\]|:::):80([[:space:]]|$)'; then
    echo
    echo "Ошибка: порт 80 уже занят:"
    ss -lntp 2>/dev/null | grep ':80 ' || true
    echo
    echo "Для standalone Certbot порт 80 должен быть свободен."
    exit 1
fi

echo "Порт 80 свободен."

# Проверка DNS
echo "[4/7] Проверка DNS..."

DOMAIN_IP=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')

if [[ -z "$DOMAIN_IP" ]]; then
    echo "Ошибка: DNS-запись для ${DOMAIN} не найдена."
    exit 1
fi

echo "${DOMAIN} -> ${DOMAIN_IP}"

# Выпуск сертификата
echo "[5/7] Выпуск сертификата..."

docker compose run --rm certbot certonly \
    --standalone \
    --preferred-challenges http \
    --non-interactive \
    --agree-tos \
    --no-eff-email \
    -d "$DOMAIN"

# Проверка сертификата
echo "[6/7] Проверка сертификата..."

CERT_FILE="${CERTBOT_DIR}/certs/live/${DOMAIN}/fullchain.pem"
KEY_FILE="${CERTBOT_DIR}/certs/live/${DOMAIN}/privkey.pem"

if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
    echo "Ошибка: сертификат выпущен, но файлы не найдены."
    exit 1
fi

echo
openssl x509 \
    -in "$CERT_FILE" \
    -noout \
    -subject \
    -issuer \
    -dates

# Установка cron
echo "[7/7] Настройка автоматического продления..."

CRON_FILE="/etc/cron.d/certbot-docker"

cat > "$CRON_FILE" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$CRON_LINE
EOF

chmod 644 "$CRON_FILE"

# Тест renewal
echo
echo "Проверка автоматического продления..."

docker compose run --rm certbot renew --dry-run

echo
echo "=============================================="
echo " ГОТОВО"
echo "=============================================="
echo
echo "Домен:"
echo "  $DOMAIN"
echo
echo "Сертификат:"
echo "  $CERT_FILE"
echo
echo "Приватный ключ:"
echo "  $KEY_FILE"
echo
echo "Автопродление:"
echo "  $CRON_FILE"
echo
echo "Cron:"
echo "  $CRON_LINE"
echo
echo "=============================================="