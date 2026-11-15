-- Часовой пояс кубка (границы дня), общее жильё и переключатель территории.
alter table cups add column if not exists timezone text not null default 'Europe/Stockholm';
alter table cups add column if not exists home_lat double precision;
alter table cups add column if not exists home_lon double precision;
-- geofence = true: в зачёт идут только точки на территории курорта.
-- false нужен для проверки дома и на тестовой горке.
alter table cups add column if not exists geofence boolean not null default true;

create unique index if not exists participants_token_idx on participants (device_token_hash);
