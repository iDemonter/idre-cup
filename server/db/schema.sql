-- Начальная схема Idre Cup. Применяется при первом запуске контейнера Postgres.

create table if not exists cups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  invite_code text not null unique,
  starts_on   date,
  days        integer not null default 6,
  prize       text,
  created_at  timestamptz not null default now()
);

create table if not exists participants (
  id                uuid primary key default gen_random_uuid(),
  cup_id            uuid not null references cups (id) on delete cascade,
  name              text not null,
  is_admin          boolean not null default false,
  -- В базе лежит только хеш токена устройства, сам токен хранится в телефоне.
  device_token_hash text not null,
  joined_at         timestamptz not null default now(),
  removed_at        timestamptz
);

create index if not exists participants_cup_idx on participants (cup_id);

-- Сырые точки GPS. Все очки сервер считает из них.
create table if not exists track_points (
  participant_id uuid not null references participants (id) on delete cascade,
  ts             timestamptz not null,
  lat            double precision not null,
  lon            double precision not null,
  altitude_m     real,
  speed_mps      real,
  h_accuracy_m   real,
  primary key (participant_id, ts)
);
