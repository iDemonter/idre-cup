-- Дуэли один на один. Итог сервер считает сам по трекам обоих за время дуэли.
create table if not exists duels (
  id               uuid primary key default gen_random_uuid(),
  cup_id           uuid not null references cups (id) on delete cascade,
  challenger_id    uuid not null references participants (id) on delete cascade,
  opponent_id      uuid not null references participants (id) on delete cascade,
  -- race: лучшее время на трассе; speed: максимальная скорость; endurance: перепад высот.
  kind             text not null check (kind in ('race', 'speed', 'endurance')),
  trail            integer,
  minutes          integer not null,
  stake            integer not null,
  -- pending: ждёт ответа; active: идёт (и подсчёт после конца); finished: есть итог;
  -- declined, cancelled, expired: не состоялась, очки не двигаются.
  status           text not null default 'pending'
                   check (status in ('pending', 'active', 'finished', 'declined', 'cancelled', 'expired')),
  created_at       timestamptz not null default now(),
  starts_at        timestamptz,
  ends_at          timestamptz,
  winner_id        uuid references participants (id) on delete set null,
  challenger_value double precision,
  opponent_value   double precision,
  settled_at       timestamptz
);

create index if not exists duels_cup_idx on duels (cup_id, created_at desc);
