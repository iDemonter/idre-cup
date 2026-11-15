# Idre Cup

Приложение для iPhone: недельное соревнование друзей на горнолыжном курорте Idre Fjäll.
Рейтинг по GPS, короны трасс, дуэли, вечерние игры.

Состояние: **шаг 1 из 5**. Приложение показывает рельеф Apple Maps над Idre Fjäll, сервер умеет отвечать на проверку здоровья и отдавать правила.

## Что где лежит

| Папка | Что внутри |
|---|---|
| `app/` | Приложение на SwiftUI. Проект Xcode в репозитории не хранится, его создаёт XcodeGen из `app/project.yml`. |
| `server/` | Сервер: Node, Postgres, Docker. Считает очки по сырым трекам. |
| `.github/workflows/ios.yml` | Сборка и отправка в TestFlight. |

## Сборка приложения

Mac для разработки нет, всё собирает GitHub Actions на `macos-26`.

- **Проверочная сборка** запускается на каждый коммит в `app/`. Компилирует под симулятор, секреты не нужны.
- **TestFlight** запускается для ветки `main`: архив, подпись облачным сертификатом Apple, отправка. Если секреты не заданы, шаг пропускается с пояснением.

Номер сборки берётся из номера запуска, вручную его менять не нужно.

### Секреты репозитория

Settings → Secrets and variables → Actions → New repository secret.

| Секрет | Что это | Где взять |
|---|---|---|
| `ASC_KEY_ID` | ID ключа App Store Connect API | App Store Connect → Users and Access → Integrations → App Store Connect API |
| `ASC_ISSUER_ID` | Issuer ID | там же, над списком ключей |
| `ASC_KEY_P8` | Содержимое файла `AuthKey_XXXX.p8` целиком | скачивается один раз при создании ключа |
| `APPLE_TEAM_ID` | Team ID, 10 символов | developer.apple.com → Account → Membership details |

Ключу нужна роль **Admin**: только с ней Apple разрешает подпись облачным сертификатом распространения.

В коде секретов нет и быть не должно: репозиторий публичный.

### Идентификатор приложения

`com.idemonter.idrecup`. Он должен быть зарегистрирован в Certificates, Identifiers & Profiles, и для него должна быть создана запись приложения в App Store Connect.

## Трассы на карте

Линии трасс и подъёмников взяты из OpenStreetMap, номера, зоны и сложность из официальной карты трасс Idre Fjäll 2026/27.

- `data/osm-idre.json` — сырые данные OpenStreetMap. Обновляет workflow «Данные трасс» (`tools/fetch_osm.py`).
- `tools/build_pistes.py` — собирает из них `app/IdreCup/Resources/pistes.json`, который читает приложение.

На карте все 41 трасса. По названию в OpenStreetMap находятся 35, остальные сопоставлены вручную в `tools/build_pistes.py`:

- 39 Glidaren, 40 Gondolsvängen и низ 41 Pernillabacken: в OpenStreetMap это линии без названия, номер назначен по положению (таблица `UNNAMED`).
- 7 Äventyret и 8 Snowpark: в OpenStreetMap записаны как «Snowpark röd» и «Snowpark grön/blå» (таблица `ALIASES`).
- 2 Familjeparken и 3 Askes skidområde: в OpenStreetMap их нет, нарисованы от руки (таблица `DRAWN`). На карте они пунктирные, точность 30–50 м.

Сопоставление по положению стоит проверить на месте.

Данные карты: © участники OpenStreetMap, лицензия ODbL.

## Сервер

```bash
cd server
cp .env.example .env      # задать POSTGRES_PASSWORD
docker compose up -d --build
curl http://127.0.0.1:8080/health
```

- `GET /health` — сервер жив, база отвечает.
- `GET /v1/config` — правила и очки из `server/config/rules.json`. Меняются без новой сборки приложения.

Тесты: `cd server && npm install && npm test`.

Порт открыт только на самом мини-ПК. Наружу сервер будет выходить через туннель, это следующий шаг.

## План

1. Репозиторий, сборка, первая сборка в TestFlight с картой, каркас сервера. **← сейчас**
2. Создание кубка и вход по коду, трекинг, определение спусков, рейтинг, «Мой день».
3. Трассы, треки и короны поверх карты, автогонки.
4. Дуэли, события и пуши, Live Activity.
5. Вечерние игры и церемония.
