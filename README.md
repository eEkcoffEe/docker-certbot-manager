# Docker Certbot Manager

Автоматический выпуск и продление SSL-сертификатов Let's Encrypt через Certbot в Docker.

Скрипт позволяет выпустить сертификат для домена **одной командой**, без клонирования репозитория и без ручного создания конфигурации Certbot.

## Возможности

* Выпуск SSL-сертификатов Let's Encrypt.
* Certbot запускается в Docker.
* Используется HTTP-01 challenge через `standalone`.
* Автоматическое создание `/opt/certbot`.
* Автоматическое создание `docker-compose.yml`.
* Проверка DNS-записи домена.
* Проверка TCP-порта `80`.
* Автоматическая настройка cron для продления сертификатов.
* Проверка продления через `--dry-run`.
* Поддержка нескольких доменов.
* Все сертификаты хранятся в одном каталоге.
* Запуск скрипта напрямую из GitHub без клонирования репозитория.

## Требования

На сервере должны быть установлены:

* Docker
* Docker Compose Plugin
* `curl`
* `openssl`
* `iproute2` (`ss`)
* cron

Скрипт необходимо запускать от `root`.

## Быстрый запуск

Для выпуска сертификата достаточно выполнить:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eEkcoffEe/docker-certbot-manager/main/issue-cert.sh) paypalobjects.duckdns.org
```

Замените `paypalobjects.duckdns.org` на нужный домен.

Например:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eEkcoffEe/docker-certbot-manager/main/issue-cert.sh) node01.duckdns.org
```

Репозиторий клонировать не требуется.

Скрипт загружается напрямую из GitHub и сразу выполняется.

## Как это работает

При запуске:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eEkcoffEe/docker-certbot-manager/main/issue-cert.sh) DOMAIN
```

скрипт:

1. Проверяет запуск от `root`.
2. Проверяет наличие Docker.
3. Проверяет Docker Compose.
4. Создаёт `/opt/certbot`.
5. Создаёт Docker Compose.
6. Проверяет DNS домена.
7. Проверяет TCP-порт `80`.
8. Запускает Certbot.
9. Выпускает сертификат Let's Encrypt.
10. Проверяет полученный сертификат.
11. Настраивает автоматическое продление.
12. Выполняет тестовое продление через `--dry-run`.

## Docker Compose

Скрипт создаёт:

```yaml
services:
  certbot:
    container_name: certbot
    image: certbot/certbot
    network_mode: host
    volumes:
      - ./certs:/etc/letsencrypt
```

Использование `network_mode: host` позволяет Certbot напрямую использовать TCP-порт `80` для HTTP-01 challenge.

## Расположение сертификатов

Все сертификаты хранятся в:

```text
/opt/certbot/certs/
```

Для домена:

```text
paypalobjects.duckdns.org
```

файлы будут находиться здесь:

```text
/opt/certbot/certs/live/paypalobjects.duckdns.org/
```

Основные файлы:

```text
fullchain.pem
privkey.pem
cert.pem
chain.pem
```

Обычно приложениям нужны:

```text
/opt/certbot/certs/live/paypalobjects.duckdns.org/fullchain.pem
/opt/certbot/certs/live/paypalobjects.duckdns.org/privkey.pem
```

## Автоматическое продление

После выпуска сертификата скрипт создаёт:

```text
/etc/cron.d/certbot-docker
```

с задачей:

```cron
0 0 28 * * cd /opt/certbot && docker compose run --rm certbot renew
```

Таким образом, 28-го числа каждого месяца Certbot проверяет все существующие сертификаты и продлевает те, которым это необходимо.

Certbot не перевыпускает сертификаты без необходимости.

## Несколько доменов

Можно использовать один сервер для нескольких сертификатов.

Например:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eEkcoffEe/docker-certbot-manager/main/issue-cert.sh) paypalobjects.duckdns.org
```

Затем:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eEkcoffEe/docker-certbot-manager/main/issue-cert.sh) node01.duckdns.org
```

В результате:

```text
/opt/certbot/certs/live/
├── paypalobjects.duckdns.org/
└── node01.duckdns.org/
```

Один общий cron будет обслуживать все сертификаты:

```bash
cd /opt/certbot
docker compose run --rm certbot renew
```

## Требования для выпуска сертификата

Для `standalone` необходимо:

### DNS

Домен должен указывать на IP-адрес сервера.

Например:

```text
paypalobjects.duckdns.org
        ↓
176.124.204.30
```

### TCP/80

Порт `80` должен быть доступен из интернета.

Например:

```text
Internet
   ↓
TCP/80
   ↓
Server
   ↓
Certbot
```

Если порт `80` закрыт firewall, Let's Encrypt не сможет проверить домен.

Порт должен быть открыт:

* во внешнем firewall VPS;
* в `ufw`, если он используется;
* в `iptables`/`nftables`, если используется;
* в других сетевых ACL.

## Проверка сертификата

Посмотреть срок действия:

```bash
openssl x509 \
  -in /opt/certbot/certs/live/paypalobjects.duckdns.org/fullchain.pem \
  -noout \
  -subject \
  -issuer \
  -dates
```

Посмотреть сертификаты Certbot:

```bash
cd /opt/certbot
docker compose run --rm certbot certificates
```

Проверить автоматическое продление:

```bash
cd /opt/certbot
docker compose run --rm certbot renew --dry-run
```

При успешной проверке должно появиться:

```text
Congratulations, all simulated renewals succeeded
```

## Важный момент после продления

Certbot обновляет файлы сертификатов, но приложение, использующее сертификат, может продолжать использовать старую версию.

Например, это может быть:

* Nginx
* Apache
* Caddy
* Xray
* RemnaNode
* другой сервис

В таком случае после обновления сертификата необходимо выполнить `reload` или перезапуск соответствующего сервиса.

Для таких случаев можно добавить Certbot `deploy-hook`.

Пример:

```bash
certbot renew --deploy-hook "systemctl reload nginx"
```

Конкретный hook зависит от сервиса, который использует сертификат.

## Структура проекта

```text
docker-certbot-manager/
├── README.md
└── issue-cert.sh
```

## Репозиторий

GitHub:

https://github.com/eEkcoffEe/docker-certbot-manager

Скрипт:

https://raw.githubusercontent.com/eEkcoffEe/docker-certbot-manager/main/issue-cert.sh

## Лицензия

MIT
