#!/usr/bin/env bash

set -euo pipefail

CERTBOT_DIR="/opt/certbot"
COMPOSE_FILE="${CERTBOT_DIR}/docker-compose.yml"
CRON_FILE="/etc/cron.d/certbot-docker"

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

# --------------------------------------------------
# Проверка root
# --------------------------------------------------

if [[ "$EUID" -ne 0 ]]; then
    echo "Ошибка: скрипт необходимо запускать от root."
    exit 1
fi

# --------------------------------------------------
# Установка Docker
# --------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
    echo
    echo "[1/8] Docker не установлен."
    echo "Устанавливаем Docker..."

    curl -fsSL https://get.docker.com | sh

    systemctl enable --now docker

    echo "Docker установлен."
else
    echo
    echo "[1/8] Docker уже установлен."
fi

# --------------------------------------------------
# Проверка Docker
# --------------------------------------------------

echo
echo "[2/8] Проверка Docker..."

if ! docker info >/dev/null 2>&1; then
    echo "Ошибка: Docker установлен, но не запущен."

    systemctl enable --now docker

    if ! docker info >/dev/null 2>&1; then
        echo "Ошибка: не удалось запустить Docker."
        exit 1
    fi
fi

echo "Docker работает."

# --------------------------------------------------
# Проверка Docker Compose
# --------------------------------------------------

echo
echo "[3/8] Проверка Docker Compose..."

if ! docker compose version >/dev/null 2>&1; then
    echo "Ошибка: Docker Compose Plugin не найден."
    exit 1
fi

docker compose version

# --------------------------------------------------
# Создание Certbot
# --------------------------------------------------

echo
echo "[4/8] Создание каталога Certbot..."

mkdir -p "${CERTBOT_DIR}/certs"

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

# --------------------------------------------------
# Проверка порта 80
# --------------------------------------------------

echo
echo "[5/8] Проверка TCP-порта 80..."

if ss -lntp 2>/dev/null | grep -qE '(^|[[:space:]])(0\.0\.0\.0|\[::\]|:::):80([[:space:]]|$)'; then
    echo
    echo "Ошибка: порт 80 уже занят."

    ss -lntp 2>/dev/null | grep ':80 ' || true

    echo
    echo "Для standalone Certbot порт 80 должен быть свободен."
    exit 1
fi

echo "Порт 80 свободен."

# --------------------------------------------------
# Проверка DNS
# --------------------------------------------------

echo
echo "[6/8] Проверка DNS..."

DOMAIN_IP=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')

if [[ -z "$DOMAIN_IP" ]]; then
    echo
    echo "Ошибка: DNS-запись для ${DOMAIN} не найдена."
    exit 1
fi

echo "${DOMAIN} -> ${DOMAIN_IP}"

# --------------------------------------------------
# Выпуск сертификата
# --------------------------------------------------

echo
echo "[7/8] Выпуск SSL-сертификата..."

docker compose run --rm certbot certonly \
    --standalone \
    --preferred-challenges http \
    --non-interactive \
    --agree-tos \
    --no-eff-email \
    -d "$DOMAIN"

CERT_FILE="${CERTBOT_DIR}/certs/live/${DOMAIN}/fullchain.pem"
KEY_FILE="${CERTBOT_DIR}/certs/live/${DOMAIN}/privkey.pem"

if [[ ! -f "$CERT_FILE" || ! -f "$KEY_FILE" ]]; then
    echo
    echo "Ошибка: сертификат выпущен, но файлы не найдены."
    exit 1
fi

echo
echo "Сертификат успешно выпущен."

openssl x509 \
    -in "$CERT_FILE" \
    -noout \
    -subject \
    -issuer \
    -dates

# --------------------------------------------------
# Настройка автоматического продления
# --------------------------------------------------

echo
echo "[8/8] Настройка автоматического продления..."

cat > "$CRON_FILE" <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 0 28 * * cd /opt/certbot && docker compose run --rm certbot renew
EOF

chmod 644 "$CRON_FILE"

echo "Cron создан:"
echo "  $CRON_FILE"

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
echo "Автоматическое продление:"
echo "  $CRON_FILE"
echo
echo "Cron:"
echo "  0 0 28 * * cd /opt/certbot && docker compose run --rm certbot renew"
echo
echo "=============================================="
