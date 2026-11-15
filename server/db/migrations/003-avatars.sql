-- Аватар участника: небольшая картинка (JPEG или PNG) прямо в базе.
-- avatar_version растёт при каждой замене: по нему телефоны понимают, что картинку пора скачать заново.
alter table participants add column if not exists avatar bytea;
alter table participants add column if not exists avatar_version integer not null default 0;
