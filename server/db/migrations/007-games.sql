-- Вечерние игры. Каждый телефон сам меряет время и присылает результат.
create table if not exists games (
  id          uuid primary key default gen_random_uuid(),
  cup_id      uuid not null references cups (id) on delete cascade,
  day         date not null,
  kind        text not null check (kind in ('reaction')),
  -- open: идёт приём результатов; finished: есть места и очки.
  status      text not null default 'open' check (status in ('open', 'finished')),
  created_at  timestamptz not null default now(),
  closes_at   timestamptz not null,
  -- Задержки до зелёного в каждом раунде, мс: одинаковые у всех.
  delays      jsonb not null,
  -- participant_id → { "times": [мс или null за фальстарт], "score": средняя с штрафами }
  entries     jsonb not null default '{}',
  results     jsonb
);

create index if not exists games_cup_idx on games (cup_id, created_at desc);
