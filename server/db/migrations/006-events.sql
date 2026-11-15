-- События дня: короткие задания для всего кубка. Время и вид выбирает сервер.
create table if not exists events (
  id         uuid primary key default gen_random_uuid(),
  cup_id     uuid not null references cups (id) on delete cascade,
  day        date not null,
  -- Номер события в расписании дня (1, 2, 3). У события, запущенного админом вручную, номера нет.
  slot       integer,
  -- double, best, explore или hunt. Вид выбирается в момент начала, до этого пусто.
  kind       text,
  -- scheduled: ждёт своего времени; active: идёт (и подсчёт после конца); finished: есть итог;
  -- skipped: не состоялось (никто не катался).
  status     text not null default 'scheduled' check (status in ('scheduled', 'active', 'finished', 'skipped')),
  starts_at  timestamptz not null,
  ends_at    timestamptz,
  -- Для охоты: кто был лидером в момент начала.
  leader_id  uuid references participants (id) on delete set null,
  -- Итог: { "awards": [ { "id": участник, "points": очки } ] }
  results    jsonb,
  settled_at timestamptz
);

create index if not exists events_cup_day_idx on events (cup_id, day);
create unique index if not exists events_slot_idx on events (cup_id, day, slot);
