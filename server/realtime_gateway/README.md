# Cernogram Realtime Gateway v1

Первый собственный низколатентный транспорт Cernogram. Gateway принимает один WebSocket-сеанс от клиента, мультиплексирует комнаты и не получает ключи шифрования или открытый текст сообщений.

## Что уже реализовано

- `wss://host/v1/realtime` и `GET /health`;
- подписанные короткоживущие access token;
- подписка на несколько комнат через одно соединение;
- стабильный `packetId`, защита от дублей и `event_ack`;
- `roomSeq`, `serverSeq`, resume cursor и replay;
- store-and-forward с TTL;
- presence по профилям и устройствам;
- JSON-хранилище без базы данных;
- каждая комната делится на чанки максимум по 500 событий;
- сервер сохраняет только ciphertext и служебные поля маршрутизации.

## Локальный запуск

```bash
cd server/realtime_gateway
dart pub get
export CG_GATEWAY_SIGNING_SECRET='replace-with-at-least-32-random-characters'
dart run bin/server.dart
```

Для изолированного локального теста без token можно временно установить:

```bash
export CG_DEV_ALLOW_ANONYMOUS=true
```

Этот режим запрещено включать на публичном сервере.

## Выпуск тестового token

```bash
export CG_GATEWAY_SIGNING_SECRET='replace-with-at-least-32-random-characters'
dart run tool/mint_token.dart profile-1 android-main room-a,room-b 12
```

## Docker

```bash
docker build -t cernogram-realtime .
docker run --rm -p 8080:8080 \
  -e CG_GATEWAY_SIGNING_SECRET='replace-with-at-least-32-random-characters' \
  -v cernogram-realtime-data:/data \
  cernogram-realtime
```

В production перед контейнером ставится TLS reverse proxy. Клиент подключается только по `wss://` на 443.

## Хранение

```text
data/
  server_state.json
  rooms/<sha256-room-id>/
    room_meta.json
    events_000001.json
    events_000002.json
  cursors/<sha256-profile-device>.json
```

В одном `events_XXXXXX.json` не бывает больше 500 записей. PostgreSQL и другие базы данных не используются.

## Протокол

Полная схема находится в `docs/realtime_protocol_v1.md` в корне проекта. Клиент должен подтверждать полученные события frame `ack`, после чего cursor устройства сохраняется. При reconnect клиент передаёт последний известный `roomSeq`; gateway возвращает только непринятые события.

## Следующие шаги

1. Автоматические интеграционные тесты двух WebSocket-клиентов.
2. Подключаемый Flutter transport под feature flag.
3. Серверная выдача короткоживущего token.
4. Push wake-up Android.
5. Развёртывание TLS, мониторинга и резервного экземпляра.
