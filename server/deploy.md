# Запуск сервера Idre Cup

Сервер живёт в двух контейнерах: API (Node) и своя база Postgres. Стек изолирован: своё имя проекта `idre-cup`, своя сеть и свой том. API слушает только `127.0.0.1`, наружу выходит через туннель, порты на роутере не открываются.

## Первый запуск

```bash
git clone https://github.com/iDemonter/idre-cup ~/idre-cup
cd ~/idre-cup/server
cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
sed -i "s/^APP_VERSION=.*/APP_VERSION=$(git rev-parse --short HEAD)/" .env
chmod 600 .env
docker compose up -d --build
curl http://127.0.0.1:8080/health    # {"ok":true,...,"db":true}
```

Если порт 8080 занят, поменяйте `API_PORT` в `.env`.

## Обновление

```bash
cd ~/idre-cup && git pull
cd server
sed -i "s/^APP_VERSION=.*/APP_VERSION=$(git rev-parse --short HEAD)/" .env
docker compose up -d --build
```

Схему базы сервер обновляет сам при запуске: файлы `db/migrations/*.sql` применяются по порядку, каждый один раз.

## Копия базы

```bash
docker compose exec db pg_dump -U idrecup idrecup | gzip > ~/idre-cup-$(date +%F).sql.gz
```

## Адрес в интернете

Телефонам нужен постоянный HTTPS-адрес, который ведёт на `http://127.0.0.1:8080`. Подходят Cloudflare Tunnel (нужен домен) и Tailscale Funnel. Адрес приложение берёт из настроек, поэтому сервер можно переносить без новой сборки.
