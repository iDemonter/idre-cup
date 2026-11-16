#!/usr/bin/env bash
# Автообновление сервера Idre Cup из GitHub (main). Запуск по cron каждые 5 минут, см. deploy.md.
#
# Что делает:
#   1. git fetch. Если на main ничего нового — тихо выходит.
#   2. Не трогает рабочую папку, если в ней есть свои незакоммиченные правки или неотправленные коммиты:
#      пишет об этом в лог и ждёт.
#   3. Если сервер (server/) не менялся — просто git pull (обновятся документы, данные карты и т. п.).
#   4. Если менялся — ждёт, пока на GitHub пройдёт проверка «Сервер» (тесты + сборка образа) именно
#      для этого коммита. Проверка упала — не ставит, ждёт следующего коммита.
#   4а. Снимает копию базы (backup.sh: локально и на NAS). Копия не снялась — не ставит, пробует снова.
#   5. git pull, APP_VERSION в .env, docker compose up -d --build.
#   6. Проверяет http://127.0.0.1:API_PORT/health: должен ответить с новой версией и db:true.
#      Не ответил за 2 минуты — откатывается на прошлый коммит, пересобирает и запоминает плохой
#      коммит, чтобы не пробовать его снова.
#
# Трогает только свою папку и свой compose-проект idre-cup. Секреты не печатает.
# Ручной запуск: ./auto-update.sh          (обычный)
#                ./auto-update.sh --force  (пересобрать даже без новых коммитов)
set -euo pipefail

cd "$(dirname "$0")"   # → server/
SERVER_DIR="$PWD"
REPO_DIR="$(git rev-parse --show-toplevel)"
REPO_SLUG="iDemonter/idre-cup"
BRANCH="main"

env_get() { sed -n "s/^$1=//p" .env 2>/dev/null | tr -d "\"'\r" | tail -1; }
log() { echo "$(date '+%F %T') $*"; }

PORT="$(env_get API_PORT)"; PORT="${PORT:-8080}"
STATE_DIR="${IDRE_STATE_DIR:-$HOME/.idre-cup}"
mkdir -p "$STATE_DIR"
BAD_FILE="$STATE_DIR/bad-commit"
WAIT_FILE="$STATE_DIR/waiting-for"

# Один запуск за раз: если прошлый ещё собирает образ, этот просто выходит.
exec 9>"$STATE_DIR/auto-update.lock"
flock -n 9 || exit 0

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

cd "$REPO_DIR"
git fetch -q origin "$BRANCH"
LOCAL="$(git rev-parse HEAD)"
REMOTE="$(git rev-parse "origin/$BRANCH")"

if [ "$LOCAL" = "$REMOTE" ] && [ "$FORCE" = 0 ]; then
  exit 0
fi

# Свои правки на машине не затираем.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  log "пропуск: в $REPO_DIR есть незакоммиченные правки (git status). Закоммитьте и отправьте их или отмените."
  exit 0
fi
if [ -n "$(git rev-list "origin/$BRANCH..HEAD")" ]; then
  log "пропуск: есть локальные коммиты, которых нет на GitHub. Сделайте git push (или git pull --rebase, затем push)."
  exit 0
fi

if [ "$(cat "$BAD_FILE" 2>/dev/null)" = "$REMOTE" ] && [ "$FORCE" = 0 ]; then
  exit 0   # этот коммит уже не запустился, ждём следующего
fi

SERVER_CHANGED=0
if [ "$FORCE" = 1 ] || [ -n "$(git diff --name-only "$LOCAL" "$REMOTE" -- server .github/workflows/server.yml)" ]; then
  SERVER_CHANGED=1
fi

if [ "$SERVER_CHANGED" = 0 ]; then
  git merge -q --ff-only "origin/$BRANCH"
  log "обновлено без перезапуска: $(git rev-parse --short HEAD) (сервер не менялся)"
  exit 0
fi

# Последний коммит, который трогал сервер: для него на GitHub должна быть зелёная проверка «Сервер».
CHECK_SHA="$(git log -1 --format=%H "origin/$BRANCH" -- server .github/workflows/server.yml)"
if [ "$FORCE" = 0 ]; then
  RUNS="$(curl -fsS --max-time 20 -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO_SLUG/actions/workflows/server.yml/runs?head_sha=$CHECK_SHA&per_page=5" || true)"
  if [ -z "$RUNS" ]; then
    log "GitHub не ответил, попробую позже"
    exit 0
  fi
  if ! echo "$RUNS" | grep -q '"conclusion": *"success"'; then
    if echo "$RUNS" | grep -q '"conclusion": *"failure"'; then
      MSG="проверка «Сервер» для ${CHECK_SHA:0:7} не прошла — не ставлю, жду исправления"
    else
      MSG="жду проверку «Сервер» для ${CHECK_SHA:0:7}"
    fi
    # В лог пишем один раз на коммит, а не каждые 5 минут.
    if [ "$(cat "$WAIT_FILE" 2>/dev/null)" != "$MSG" ]; then
      log "$MSG"
      echo "$MSG" > "$WAIT_FILE"
    fi
    exit 0
  fi
fi

# Копия базы перед выкаткой: новая версия может принести миграцию, а откат ниже возвращает только код.
# backup.sh: 0 — копия есть; 2 — локальная копия есть, NAS не ответил (ставим, но пишем); иначе — не ставим.
if [ -n "$(cd "$SERVER_DIR" && docker compose ps -q --status running db 2>/dev/null)" ]; then
  BACKUP_RC=0
  "$SERVER_DIR/backup.sh" || BACKUP_RC=$?
  if [ "$BACKUP_RC" = 2 ]; then
    log "копия базы только локальная (NAS не ответил), продолжаю"
  elif [ "$BACKUP_RC" != 0 ]; then
    MSG="копия базы не снялась (backup.sh, код $BACKUP_RC) — не ставлю, попробую в следующий раз"
    if [ "$(cat "$WAIT_FILE" 2>/dev/null)" != "$MSG" ]; then
      log "$MSG"
      echo "$MSG" > "$WAIT_FILE"
    fi
    exit 0
  fi
else
  log "база не запущена — ставлю без копии (первый запуск?)"
fi
rm -f "$WAIT_FILE"

deploy() {
  cd "$REPO_DIR/server"
  local short; short="$(git rev-parse --short HEAD)"
  sed -i "s/^APP_VERSION=.*/APP_VERSION=$short/" .env
  grep -q '^APP_VERSION=' .env || echo "APP_VERSION=$short" >> .env
  docker compose up -d --build --remove-orphans >/dev/null 2>&1
  cd "$REPO_DIR"
}

healthy() {
  local short="$1" body
  for _ in $(seq 1 24); do
    body="$(curl -fsS --max-time 5 "http://127.0.0.1:$PORT/health" 2>/dev/null || true)"
    if echo "$body" | grep -q "\"version\":\"$short\"" && echo "$body" | grep -q '"db":true'; then
      return 0
    fi
    sleep 5
  done
  return 1
}

PREV="$LOCAL"
git merge -q --ff-only "origin/$BRANCH"
NEW_SHORT="$(git rev-parse --short HEAD)"
log "ставлю $NEW_SHORT (было ${PREV:0:7})"

if deploy && healthy "$NEW_SHORT"; then
  rm -f "$BAD_FILE"
  log "готово: сервер работает на $NEW_SHORT"
  docker image prune -f --filter "label=com.docker.compose.project=idre-cup" >/dev/null 2>&1 || true
  exit 0
fi

log "ОШИБКА: $NEW_SHORT не поднялся, откатываюсь на ${PREV:0:7}"
echo "$REMOTE" > "$BAD_FILE"
(cd server && docker compose logs --tail 40 api 2>&1 | grep -viE 'password|token|secret' | sed 's/^/    /') || true
git reset -q --hard "$PREV"
if deploy && healthy "$(git rev-parse --short HEAD)"; then
  log "откат готов: сервер снова на ${PREV:0:7}"
else
  log "ОШИБКА: и после отката /health не отвечает — нужно смотреть руками (docker compose ps / logs)"
fi
exit 1
