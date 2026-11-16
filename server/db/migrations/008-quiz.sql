-- Викторина: тот же список игр, вопросы и ответы хранятся у игры.
alter table games drop constraint if exists games_kind_check;
alter table games add constraint games_kind_check check (kind in ('reaction', 'quiz'));
alter table games add column if not exists questions jsonb;
-- participant_id → { "номер вопроса": { "choice": 0..3, "ms": время ответа, "points": очки } }
alter table games add column if not exists answers jsonb not null default '{}';
