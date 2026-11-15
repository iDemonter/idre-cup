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

Ночную копию делает `backup.sh`: дамп в `~/idre-cup-backups` (14 дней) и, если в `.env` задан `BACKUP_NAS=user@host`, rsync по SSH-ключу в `idre-cup-backups` на NAS (90 дней). Строка для `crontab -e`:

```
45 3 * * * /home/hermes/idre-cup/server/backup.sh >> /home/hermes/idre-cup-backups/backup.log 2>&1
```

Восстановление:

```bash
gunzip -c ~/idre-cup-backups/idrecup_ДАТА.sql.gz | docker compose exec -T db psql -U idrecup -d idrecup
```

## Адрес в интернете

Телефонам нужен постоянный HTTPS-адрес. Его даёт свой туннель Cloudflare: контейнер `cloudflared` в этом же стеке ходит к API по сети стека (`http://api:8080`). С другими туннелями на машине он не пересекается. Адрес приложение берёт из настроек, поэтому сервер можно переносить без новой сборки.

1. Cloudflare Zero Trust → Networks → Tunnels → Create a tunnel, тип Cloudflared, имя `idre-cup`.
2. На шаге установки скопируйте токен (длинная строка после `--token`). Команду установки не запускайте: cloudflared уже есть в compose.
3. Public hostname: свой поддомен, Service `HTTP`, URL `api:8080`.
4. На сервере допишите в `.env` профиль и токен. Токен вводится без эха и не попадает в историю shell:

   ```bash
   cd ~/idre-cup/server
   read -rsp "Токен туннеля: " T && echo && printf 'COMPOSE_PROFILES=tunnel\nCLOUDFLARE_TUNNEL_TOKEN=%s\n' "$T" >> .env && unset T
   chmod 600 .env
   docker compose up -d
   docker compose logs cloudflared | grep -i registered   # четыре строки Registered tunnel connection
   curl https://<ваш поддомен>/health
   ```

С `COMPOSE_PROFILES=tunnel` в `.env` обычное обновление (`docker compose up -d --build`) поднимает и туннель. Отключить туннель: удалить строку `COMPOSE_PROFILES` и выполнить `docker compose stop cloudflared`.
