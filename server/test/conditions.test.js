// Разбор страниц курортов на сохранённых образцах (без сети).
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { closingTime, htmlLines, parseHours, parseIdre, parseSkiStockholm, parseSkistar, summarizeForecast } from "../src/conditions.js";

const lines = (name) => readFileSync(new URL(`./fixtures/${name}`, import.meta.url), "utf8").split("\n").filter(Boolean);

test("htmlLines: теги, скрипты и сущности", () => {
  assert.deepEqual(htmlLines("<div>Temperatur &amp; vind</div><script>x()</script><p> 5&nbsp;m/s </p><b>&#246;ppen</b>"), ["Temperatur & vind", "5 m/s", "öppen"]);
});

test("часы работы: каждый день и по дням недели", () => {
  assert.deepEqual(parseHours("🕘 09.00-17.00"), { opens: "09:00", closes: "17:00", days: null });
  assert.deepEqual(parseHours("🕘 Mån–tors 09.00-17.00").days, [1, 2, 3, 4]);
  assert.deepEqual(parseHours("Fre–sön 07.00–19.00"), { opens: "07:00", closes: "19:00", days: [5, 6, 0] });
  assert.equal(parseHours("Öppnar 8 februari"), null);
});

test("Idre Fjäll: счётчики, снег, погода, лифты с часами", () => {
  const status = parseIdre(lines("idre-status.txt"));
  assert.deepEqual(status.lifts, { open: 2, total: 24 });
  assert.deepEqual(status.snow, { piste: 45, terrain: 38, fresh: 4 });
  assert.deepEqual(status.weather.top, { temp: -12, wind: 6, gust: 9, direction: "NV" });
  assert.equal(status.liftList.length, 3);
  const tall = status.liftList.find((lift) => lift.code === "L");
  assert.equal(tall.hours.length, 2);
  assert.equal(tall.status, "open");
  assert.equal(status.liftList.find((lift) => lift.code === "G").comment, "Vind");
  assert.equal(closingTime(status, 2), "16:00", "вторник: Nord 6:an и Talliften до 16:00");
  assert.equal(closingTime(status, 6), "16:30", "суббота: Talliften до 16:30");
});

test("SkiStar: лифты, трассы, часы без вечернего катания, погода, снег", () => {
  const status = parseSkistar(lines("skistar-are-by.txt"));
  assert.deepEqual(status.lifts, { open: 3, total: 16 });
  assert.deepEqual(status.pistes, { open: 5, total: 40 });
  assert.deepEqual(status.liftList.map((lift) => [lift.code, lift.status]), [["Å22", "open"], ["Å30", "closed"], ["Å33", "open"], ["Å40", "open"]]);
  assert.deepEqual(status.pisteList.map((piste) => piste.ref), ["31", "32", "57"]);
  assert.equal(status.hours.find((rule) => rule.code === "Å22").closes, "16:30");
  assert.equal(status.season, "11 december - 7 februari");
  assert.equal(closingTime(status, 3), "16:30", "Bergbanan до 22:00 — вечернее катание, не считается");
  assert.deepEqual(status.weather.top, { temp: -6, wind: 8, gust: 9 });
  assert.equal(status.weather.sky, "Dimma");
  assert.deepEqual(status.snow, { terrain: 29, piste: 40, last24h: 9, last72h: 19 });
});

test("прогноз MET Norway: сводка на день", () => {
  const json = JSON.parse(readFileSync(new URL("./fixtures/met-forecast.json", import.meta.url), "utf8"));
  const forecast = summarizeForecast(json, "Europe/Stockholm");
  assert.ok(forecast.day.min <= forecast.day.max);
  assert.equal(forecast.day.text, "небольшой снег");
  assert.ok(forecast.hours.length <= 12);
});

test("Ski Stockholm (Väsjöbacken): счётчики и часы по дням недели", () => {
  const status = parseSkiStockholm(lines("skistockholm-vasjobacken.txt"));
  assert.deepEqual(status.pistes, { open: 3, total: 5 });
  assert.deepEqual(status.lifts, { open: 4, total: 5 });
  assert.equal(status.liftList.length, 5);
  assert.deepEqual(status.pisteList.map((piste) => piste.name), ["Familjebacken", "Slingan", "Huvudbacken", "Klubbacken"]);
  assert.equal(closingTime(status, 6), "16:00", "суббота 10–16");
  assert.equal(closingTime(status, 2), "21:00", "будни: горка работает только вечером, до 21:00");
});
