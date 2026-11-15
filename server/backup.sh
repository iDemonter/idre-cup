#!/usr/bin/env bash
# Копия базы Idre Cup: pg_dump из контейнера db → gzip локально, затем rsync на NAS.
# Запуск по cron под пользователем с доступом к docker (sudo не нужен), см. deploy.md.
# Настройки — в .env рядом (адрес NAS в репозиторий не попадает):
#   BACKUP_NAS=user@host        куда копировать по SSH; пусто — только локальная копия
#   BACKUP_NAS_DIR=idre-cup-backups   папка на NAS (от домашней папки пользователя)
#   BACKUP_DIR=~/idre-cup-backups     локальная папка
#   BACKUP_SSH_KEY=~/.ssh/id_ed25519  ключ для NAS
# Хранение: локально 14 дней, на NAS 90 дней.
# Восстановление: gunzip -c ФАЙЛ | docker compose exec -T db psql -U idrecup -d idrecup
set -euo pipefail

cd "$(dirname "$0")"   # → server/, где docker-compose.yml и .env

env_get() { sed -n "s/^$1=//p" .env 2>/dev/null | tr -d "\"'\r" | tail -1; }
expand_home() { case "$1" in "~"/*) echo "$HOME/${1#\~/}" ;; *) echo "$1" ;; esac; }

NAS="$(env_get BACKUP_NAS)"
NAS_DIR="$(env_get BACKUP_NAS_DIR)"; NAS_DIR="${NAS_DIR:-idre-cup-backups}"
BACKUP_DIR="$(expand_home "$(env_get BACKUP_DIR)")"; BACKUP_DIR="${BACKUP_DIR:-$HOME/idre-cup-backups}"
KEY="$(expand_home "$(env_get BACKUP_SSH_KEY)")"; KEY="${KEY:-$HOME/.ssh/id_ed25519}"
LOCAL_DAYS=14
NAS_DAYS=90

mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
FILE="$BACKUP_DIR/idrecup_$(date +%Y%m%d_%H%M%S).sql.gz"
TMP="$FILE.tmp"
trap 'rm -f "$TMP"' EXIT

# -T: без TTY (cron). Пишем во временный файл, чтобы на NAS не уехал недописанный дамп.
/usr/bin/docker compose exec -T db pg_dump -U idrecup -d idrecup </dev/null | gzip > "$TMP"

# Дамп целый, только если gzip читается и pg_dump дописал финальную строку.
gunzip -c "$TMP" | tail -n 5 | grep -q 'PostgreSQL database dump complete' \
  || { echo "$(date -Is) ОШИБКА: дамп неполный, не сохраняю" >&2; exit 1; }
mv "$TMP" "$FILE"
chmod 600 "$FILE"
find "$BACKUP_DIR" -name 'idrecup_*.sql.gz' -mtime +"$LOCAL_DAYS" -delete
echo "$(date -Is) OK → $FILE ($(du -h "$FILE" | cut -f1))"

[ -n "$NAS" ] || { echo "$(date -Is) BACKUP_NAS не задан, копия только локальная"; exit 0; }

SSH="ssh -q -i $KEY -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15"
# Только файлы дампов, без логов и служебных файлов.
rsync -az --rsync-path=/usr/bin/rsync -e "$SSH" \
  --include='idrecup_*.sql.gz' --exclude='*' \
  "$BACKUP_DIR/" "$NAS:$NAS_DIR/" \
  || { echo "$(date -Is) ОШИБКА: копия на NAS не прошла" >&2; exit 2; }
$SSH "$NAS" "find $NAS_DIR -name 'idrecup_*.sql.gz' -mtime +$NAS_DAYS -delete" </dev/null || true
echo "$(date -Is) NAS OK → $NAS_DIR"
