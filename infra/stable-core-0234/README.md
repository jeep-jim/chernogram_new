# Чернограм Stable Core 0.23.4 — сервер связи

Этот стек поднимает собственные бесплатные компоненты связи:

- `gateway` — один WebSocket для чатов, файлов, подтверждений доставки, офлайн-очереди, resume и сигнализации звонков;
- `turn` — coturn для аудио- и видеозвонков в мобильных сетях, CGNAT и закрытых Wi-Fi;
- `caddy` — HTTPS/WSS и автоматический TLS-сертификат.

## Требования

- Linux-сервер с публичным IPv4;
- Docker Engine и Docker Compose;
- DNS-записи `A` для `GATEWAY_HOST` и `TURN_HOST` на `PUBLIC_IP`;
- открытые порты:
  - TCP 80 и 443;
  - UDP 443 для HTTP/3 необязателен, но разрешён стеком;
  - TCP/UDP 3478 для TURN;
  - UDP 49160–49200 для медиарелея.

## Запуск

```bash
cp .env.example .env
# Заполнить домены, IP и длинные случайные секреты.
docker compose pull
docker compose up -d --build
docker compose ps
curl --fail https://realtime.example.com/healthz
```

## Параметры клиентской сборки

Android и Windows должны собираться с одинаковыми значениями:

```text
CG_GATEWAY_ENABLED=true
CG_GATEWAY_URL=wss://realtime.example.com/v1/realtime
CG_GATEWAY_ACCESS_TOKEN=<временный токен или токен от аккаунт-сервиса>
```

Для закрытого теста можно временно выставить `CG_ALLOW_INSECURE_DEV=1` и использовать токен `dev`. Публичный релиз с таким режимом запрещён.

## Проверка TURN

Проверить доступность UDP/TCP 3478 и диапазона медиапортов с внешней сети. Клиент получает ICE-конфигурацию по `https://GATEWAY_HOST/v1/ice`; пароль TURN не хранится в интерфейсе приложения.

## Данные

Gateway пишет зашифрованные события в volume `gateway_data`. Сервер видит идентификаторы комнат, тип пакета, время и зашифрованное содержимое, но не может прочитать текст сообщения или файл без секрета комнаты.
