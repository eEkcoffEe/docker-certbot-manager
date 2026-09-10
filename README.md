# Docker Certbot Manager

Автоматический выпуск и продление SSL-сертификатов Let's Encrypt через Certbot в Docker.

Скрипт позволяет выпустить сертификат для домена **одной командой**, без клонирования репозитория и без ручного создания конфигурации Certbot.

## Возможности

* Выпуск SSL-сертификатов Let's Encrypt.
* Certbot запускается в Docker.
* Автоматическая установка Docker, если он не установлен.
* Автоматический запуск Docker.
* Использование HTTP-01 challenge через `standalone`.
* Автоматическое создание `/opt/certbot`.
* Автоматическое создание `docker-compose.yml`.
* Проверка DNS-записи домена.
* Проверка TCP-порта `80`.
* Автоматическая настройка cron для продления сертификатов.
* Проверка продления через `--dry-run`.
* Поддержка нескольких доменов на одном сервере.
* Все сертификаты хранятся в одном каталоге.
* Запуск скрипта напрямую из GitHub без клонирования репозитория.

## Требования

Скрипт необходимо запускать от `root`.

На сервере должен быть доступен:

* `curl`
* `systemd`
* `ss`
* `getent`
* `openssl`

Docker устанавливать заранее **не требуется**.

Если Docker отсутствует, скрипт автоматически устанавливает его с помощью официального Docker install script:

```bash
curl -fsSL https://get.docker.com | sh
```

После установки Docker скрипт автоматически запускает его:

```bash
systemctl enable --now docker
```

Docker Compose Plugin должен быть доступен в установленном Docker.

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

## Что делает скрипт

При запуске:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eEkcoffEe/docker-certbot-manager/main/issue-cert.sh) DOMAIN
```

скрипт выполняет следующие действия:

1. Проверяет запуск от `root`.
2. Проверяет наличие Docker.
3. Если Docker отсутствует — устанавливает его.
4. Запускает и добавляет Docker в автозагрузку.
5. Проверяет работу Docker.
6. Проверяет Docker Compose Plugin.
7. Создаёт `/opt/certbot`.
8. Создаёт `docker-compose.yml`.
9. Проверяет, свободен ли TCP-порт `80`.
10. Проверяет DNS-запись домена.
11. Запускает Certbot.
12. Выпускает SSL-сертификат Let's Encrypt.
13. Проверяет наличие файлов сертификата.
14. Показывает информацию о сертификате.
15. Создаёт cron для автоматического продления.
16. Выполняет тестовое продление через `--dry-run`.

## Docker Compose

Скрипт автоматически создаёт:

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

Например, для:

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
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

0 0 28 * * cd /opt/certbot && docker compose run --rm certbot renew
```

Таким образом, **28-го числа каждого месяца** Certbot проверяет все существующие сертификаты и продлевает те, которым это необходимо.

Certbot не перевыпускает сертификаты без необходимости.

## Несколько доменов

Один сервер может обслуживать несколько сертификатов.

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

Скрипт использует Certbot `standalone` и HTTP-01 challenge.

### DNS

Домен должен указывать на IP-адрес сервера.

Например:

```text
paypalobjects.duckdns.org
        ↓
176.124.204.30
```

Перед выпуском скрипт автоматически проверяет наличие IPv4 DNS-записи.

### TCP/80

Порт `80` должен быть доступен из интернета.

Схема проверки:

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

Также TCP/80 должен быть свободен на сервере в момент выпуска сертификата.

Если порт уже занят Nginx, Apache, Caddy или другим сервисом, скрипт остановится и сообщит об этом.

## Проверка сертификата

Посмотреть срок действия сертификата:

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

## Автоматическое продление и используемые сервисы

Certbot обновляет файлы сертификатов:

```text
fullchain.pem
privkey.pem
```

Однако приложение, которое использует сертификат, может продолжать работать со старой версией сертификата.

Например:

* Nginx
* Apache
* Caddy
* Xray
* RemnaNode
* другой сервис

После фактического обновления сертификата такому сервису может потребоваться `reload` или перезапуск.

Для этого можно использовать Certbot `deploy-hook`.

Например:

```bash
certbot renew --deploy-hook "systemctl reload nginx"
```

В текущей версии проекта `deploy-hook` автоматически не настраивается, поскольку команда перезагрузки зависит от сервиса, использующего сертификат.

## Важное замечание

Скрипт устанавливает Docker с использованием:

```bash
curl -fsSL https://get.docker.com | sh
```

Это официальный способ установки Docker Engine, предоставляемый Docker.

После установки скрипт проверяет:

```bash
docker info
```

и:

```bash
docker compose version
```

Если Docker Compose Plugin недоступен, выполнение прекращается.

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
