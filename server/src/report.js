// Отчёт о записанных треках за день: для проверки записи без доступа к приложению.
// Ничего не меняет в базе. Координаты не печатает, только время, скорость, высоту и точность.
//
// Запуск на сервере:  docker compose exec api node src/report.js [ГГГГ-ММ-ДД]
// Без даты берётся сегодняшний день по времени Стокгольма.
import pg from "pg";
import { analyze, meters } from "./analyzer.js";

const timezone = "Europe/Stockholm";
const date =
  process.argv[2] ??
  new Intl.DateTimeFormat("sv-SE", { timeZone: timezone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
const clock = (seconds) =>
  new Date(seconds * 1000).toLocaleTimeString("sv-SE", { timeZone: timezone, hour: "2-digit", minute: "2-digit", second: "2-digit" });
const minutes = (seconds) => `${Math.round(seconds / 60)} мин`;
const kmh = (mps) => `${(mps * 3.6).toFixed(1)} км/ч`;
const percentile = (values, share) => {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * share))];
};

const db = new pg.Client({ connectionString: process.env.DATABASE_URL });
await db.connect();

const people = await db.query(
  `select p.id, p.name, c.name as cup, c.geofence from participants p join cups c on c.id = p.cup_id
   where exists (select 1 from track_points t where t.participant_id = p.id
                 and t.ts >= ($1::date::timestamp at time zone $2) and t.ts < (($1::date + 1)::timestamp at time zone $2))
   order by c.name, p.name`,
  [date, timezone],
);
console.log(`Треки за ${date} (${timezone}): участников с точками ${people.rows.length}`);

for (const person of people.rows) {
  const found = await db.query(
    `select extract(epoch from ts)::float8 as t, lat, lon, coalesce(altitude_m, 0)::float8 as alt,
            coalesce(speed_mps, -1)::float8 as speed, h_accuracy_m::float8 as accuracy
     from track_points where participant_id = $1
       and ts >= ($2::date::timestamp at time zone $3) and ts < (($2::date + 1)::timestamp at time zone $3)
     order by ts`,
    [person.id, date, timezone],
  );
  const points = found.rows;
  const first = points[0];
  const last = points.at(-1);
  console.log(`\n=== ${person.name} · кубок «${person.cup}»${person.geofence ? "" : " (пробный, территория выключена)"}`);
  console.log(`Точек: ${points.length}, с ${clock(first.t)} до ${clock(last.t)} (${minutes(last.t - first.t)})`);

  // Перерывы: где телефон не присылал точки дольше минуты (пауза, выключенная запись или iOS усыпила запись).
  const gaps = [];
  let path = 0;
  for (let index = 1; index < points.length; index += 1) {
    const pause = points[index].t - points[index - 1].t;
    path += meters(points[index - 1], points[index]);
    if (pause > 60) gaps.push({ at: points[index - 1].t, pause, moved: meters(points[index - 1], points[index]) });
  }
  console.log(`Путь по точкам: ${(path / 1000).toFixed(1)} км`);
  const covered = (last.t - first.t - gaps.reduce((sum, gap) => sum + gap.pause, 0)) / Math.max(1, last.t - first.t);
  console.log(`Перерывов больше минуты: ${gaps.length}; время с точками: ${Math.round(covered * 100)} %`);
  for (const gap of gaps.sort((a, b) => b.pause - a.pause).slice(0, 12)) {
    console.log(`  ${clock(gap.at)}: нет точек ${minutes(gap.pause)}, за это время сдвиг ${(gap.moved / 1000).toFixed(2)} км`);
  }

  const speeds = points.filter((point) => point.speed >= 0).map((point) => point.speed);
  const accuracy = points.filter((point) => point.accuracy !== null).map((point) => point.accuracy);
  const heights = points.map((point) => point.alt);
  console.log(
    `Скорость GPS: макс ${kmh(Math.max(0, ...speeds))}, 95 % точек ниже ${kmh(percentile(speeds, 0.95) ?? 0)}; без скорости ${points.length - speeds.length} точек`,
  );
  console.log(
    `Точность: медиана ${percentile(accuracy, 0.5)?.toFixed(0) ?? "—"} м, 95 % лучше ${percentile(accuracy, 0.95)?.toFixed(0) ?? "—"} м; высота от ${Math.min(...heights).toFixed(0)} до ${Math.max(...heights).toFixed(0)} м`,
  );

  // Шаг между точками: при записи раз в секунду медиана около 1 с.
  const steps = points.slice(1).map((point, index) => point.t - points[index].t);
  console.log(`Шаг между точками: медиана ${percentile(steps, 0.5)?.toFixed(1) ?? "—"} с, 95 % короче ${percentile(steps, 0.95)?.toFixed(1) ?? "—"} с`);

  const stats = analyze(points);
  console.log(
    `Разбор как в приложении: спусков ${stats.runs}, перепад ${Math.round(stats.vertical)} м, на спусках ${(stats.runDistance / 1000).toFixed(1)} км, лучшая скорость ${kmh(stats.topSpeed)}`,
  );
  for (const segment of stats.segments.slice(0, 20)) {
    console.log(
      `  ${segment.kind === "run" ? "спуск " : "подъём"} ${clock(segment.start)}–${clock(segment.end)}: ${Math.round(segment.vertical)} м, ${(segment.distance / 1000).toFixed(2)} км, ${kmh(segment.topSpeed)}`,
    );
  }
  if (stats.segments.length > 20) console.log(`  … и ещё ${stats.segments.length - 20}`);
}

await db.end();
