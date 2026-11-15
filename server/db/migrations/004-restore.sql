-- Код возврата: одноразовый, живёт сутки. По нему участник входит с нового телефона и сохраняет очки.
alter table participants add column if not exists restore_code_hash text;
alter table participants add column if not exists restore_expires timestamptz;
