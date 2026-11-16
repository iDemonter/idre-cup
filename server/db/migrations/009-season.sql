-- Сезон: свои даты начала и конца (null = по умолчанию из rules.json, season.from / season.to).
alter table cups add column if not exists season_from date;
alter table cups add column if not exists season_to date;
