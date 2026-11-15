// Полный сценарий на настоящей базе: кубок, вход, треки, рейтинг.
// Нужен Postgres: TEST_DATABASE_URL=postgres://user:pass@host/db npm test
// Без этой переменной тесты пропускаются.

import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import pg from "pg";
import { createApp } from "../src/app.js";
import { migrate } from "../src/migrate.js";

const url = process.env.TEST_DATABASE_URL;
const options = { skip: url ? false : "нет TEST_DATABASE_URL" };

let db;
let server;
let base;

async function call(method, path, { token, body } = {}) {
  const res = await fetch(base + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, body: await res.json() };
}

// Трек у вершины Idre Fjäll: подъём на 200 м и спуск с заданной скоростью, раз в секунду.
function lap(startSeconds, { peakSpeed, east = 0 }) {
  const points = [];
  const lat0 = 61.8881;
  const lon0 = 12.8587 + east / 52_456;
  let t = startSeconds;
  let north = 0;
  for (let second = 0; second < 280; second += 1) {
    north += 5;
    points.push([t, lat0 + north / 111_320, lon0, 680 + (second / 280) * 200, 5, 5]);
    t += 1;
  }
  let alt = 880;
  while (alt > 680) {
    north -= peakSpeed;
    alt -= peakSpeed * 0.15;
    points.push([t, lat0 + north / 111_320, lon0, alt, peakSpeed, 5]);
    t += 1;
  }
  return points;
}

before(async () => {
  if (!url) return;
  db = new pg.Pool({ connectionString: url, max: 5 });
  await db.query("drop table if exists track_points, participants, cups, schema_migrations cascade");
  await migrate(db, () => {});
  const app = createApp({ db, version: "test" });
  await new Promise((resolve) => {
    server = app.listen(0, resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server?.close();
  await db?.end();
});

test("кубок: создать, войти по коду, увидеть участников", options, async () => {
  const created = await call("POST", "/v1/cups", { body: { cupName: "Idre Cup 2027", name: "Иван", startsOn: "2027-01-03" } });
  assert.equal(created.status, 201);
  assert.match(created.body.cup.code, /^[A-Z2-9]{6}$/);
  assert.equal(created.body.cup.startsOn, "2027-01-03");
  assert.equal(created.body.me.isAdmin, true);

  const joined = await call("POST", "/v1/join", { body: { code: created.body.cup.code.toLowerCase(), name: " Олег " } });
  assert.equal(joined.status, 201);
  assert.equal(joined.body.me.name, "Олег");
  assert.equal(joined.body.me.isAdmin, false);

  assert.equal((await call("POST", "/v1/join", { body: { code: created.body.cup.code, name: "олег" } })).body.error, "name_taken");
  assert.equal((await call("POST", "/v1/join", { body: { code: "ZZZZZZ", name: "Кто-то" } })).status, 404);
  assert.equal((await call("GET", "/v1/me")).status, 401);
  assert.equal((await call("GET", "/v1/me", { token: "wrong-token" })).status, 401);

  const me = await call("GET", "/v1/me", { token: joined.body.token });
  assert.equal(me.status, 200);
  assert.deepEqual(me.body.participants.map((person) => person.name), ["Иван", "Олег"]);
});

test("кубок: права админа, жильё, удаление", options, async () => {
  const admin = (await call("POST", "/v1/cups", { body: { cupName: "Права", name: "Админ" } })).body;
  const guest = (await call("POST", "/v1/join", { body: { code: admin.cup.code, name: "Гость" } })).body;

  assert.equal((await call("PATCH", "/v1/cup", { token: guest.token, body: { name: "Взлом" } })).status, 403);
  const home = await call("PATCH", "/v1/cup", { token: guest.token, body: { home: { lat: 61.886, lon: 12.834 } } });
  assert.deepEqual(home.body.cup.home, { lat: 61.886, lon: 12.834 });

  const renamed = await call("PATCH", `/v1/participants/${guest.me.id}`, { token: guest.token, body: { name: "Гость 2" } });
  assert.equal(renamed.body.participant.name, "Гость 2");
  assert.equal((await call("PATCH", `/v1/participants/${admin.me.id}`, { token: guest.token, body: { name: "Я" } })).status, 403);

  const recoded = await call("POST", "/v1/cup/code", { token: admin.token });
  assert.notEqual(recoded.body.cup.code, admin.cup.code);
  assert.equal((await call("POST", "/v1/join", { body: { code: admin.cup.code, name: "Поздно" } })).status, 404);

  assert.equal((await call("DELETE", `/v1/participants/${admin.me.id}`, { token: admin.token })).status, 409);
  assert.equal((await call("DELETE", `/v1/participants/${guest.me.id}`, { token: admin.token })).status, 200);
  assert.equal((await call("GET", "/v1/me", { token: guest.token })).status, 401);
  assert.equal((await call("DELETE", "/v1/participants/не-uuid", { token: admin.token })).status, 404);
});

test("аватар: загрузить, увидеть у других, убрать", options, async () => {
  const admin = (await call("POST", "/v1/cups", { body: { cupName: "Аватары", name: "Иван" } })).body;
  const guest = (await call("POST", "/v1/join", { body: { code: admin.cup.code, name: "Олег" } })).body;
  const stranger = (await call("POST", "/v1/cups", { body: { cupName: "Чужой", name: "Чужой" } })).body;
  assert.equal(admin.me.avatar, null);

  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3, 4, 0xff, 0xd9]);
  const put = (token, bytes, type) =>
    fetch(`${base}/v1/me/avatar`, { method: "PUT", headers: { authorization: `Bearer ${token}`, "content-type": type }, body: bytes });
  const saved = await put(admin.token, jpeg, "image/jpeg");
  assert.equal(saved.status, 200);
  assert.equal((await saved.json()).avatar, 1);
  assert.equal((await put(admin.token, Buffer.from("не картинка"), "image/jpeg")).status, 400);

  const people = (await call("GET", "/v1/me", { token: guest.token })).body.participants;
  assert.equal(people.find((person) => person.name === "Иван").avatar, 1);
  const seen = await fetch(`${base}/v1/participants/${admin.me.id}/avatar?v=1`, { headers: { authorization: `Bearer ${guest.token}` } });
  assert.equal(seen.status, 200);
  assert.equal(seen.headers.get("content-type"), "image/jpeg");
  assert.deepEqual(Buffer.from(await seen.arrayBuffer()), jpeg);
  const hidden = await fetch(`${base}/v1/participants/${admin.me.id}/avatar`, { headers: { authorization: `Bearer ${stranger.token}` } });
  assert.equal(hidden.status, 404, "чужой кубок аватар не видит");

  assert.equal((await call("DELETE", "/v1/me/avatar", { token: admin.token })).body.avatar, null);
  assert.equal((await call("GET", "/v1/me", { token: admin.token })).body.me.avatar, null);
});

test("возврат: по коду участник входит с нового телефона, старый отключается", options, async () => {
  const admin = (await call("POST", "/v1/cups", { body: { cupName: "Возврат", name: "Иван" } })).body;
  const guest = (await call("POST", "/v1/join", { body: { code: admin.cup.code, name: "Олег" } })).body;

  assert.equal((await call("POST", `/v1/participants/${admin.me.id}/restore`, { token: guest.token })).status, 403);
  const issued = await call("POST", `/v1/participants/${guest.me.id}/restore`, { token: admin.token });
  assert.match(issued.body.code, /^[A-Z2-9]{8}$/);
  assert.equal((await call("POST", "/v1/restore", { body: { code: "AAAAAAAA" } })).status, 404);

  const back = await call("POST", "/v1/restore", { body: { code: issued.body.code.toLowerCase() } });
  assert.equal(back.status, 200);
  assert.equal(back.body.me.id, guest.me.id);
  assert.equal(back.body.cup.id, admin.cup.id);
  assert.equal((await call("GET", "/v1/me", { token: guest.token })).status, 401, "старый телефон отключён");
  assert.equal((await call("GET", "/v1/me", { token: back.body.token })).status, 200);
  assert.equal((await call("POST", "/v1/restore", { body: { code: issued.body.code } })).status, 404, "код одноразовый");

  const own = await call("POST", `/v1/participants/${guest.me.id}/restore`, { token: back.body.token });
  assert.equal(own.status, 200, "свой код может получить и сам участник");
});

test("кубок: не больше восьми участников", options, async () => {
  const admin = (await call("POST", "/v1/cups", { body: { cupName: "Полный", name: "Первый" } })).body;
  for (let index = 2; index <= 8; index += 1) {
    assert.equal((await call("POST", "/v1/join", { body: { code: admin.cup.code, name: `Участник ${index}` } })).status, 201);
  }
  assert.equal((await call("POST", "/v1/join", { body: { code: admin.cup.code, name: "Девятый" } })).body.error, "cup_full");
});

test("треки и рейтинг: быстрее всех получает 10 очков за скорость", options, async () => {
  const today = new Date().toISOString().slice(0, 10);
  const ivan = (await call("POST", "/v1/cups", { body: { cupName: "Гонка", name: "Иван", startsOn: today } })).body;
  const oleg = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Олег" } })).body;
  const anna = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Анна" } })).body;

  // Все точки в последние 17 минут: они попадают в сегодняшний день по времени кубка
  // (если тест не запущен сразу после полуночи по Стокгольму) и в «живые» позиции за 15 минут.
  const start = Math.floor(Date.now() / 1000) - 1000;
  const ivanTrack = [...lap(start, { peakSpeed: 20 }), ...lap(start + 600, { peakSpeed: 14 })];
  const olegTrack = lap(start, { peakSpeed: 16, east: 200 });

  const sent = await call("POST", "/v1/tracks", { token: ivan.token, body: { points: ivanTrack } });
  assert.equal(sent.status, 200);
  assert.equal(sent.body.saved, ivanTrack.length);
  const again = await call("POST", "/v1/tracks", { token: ivan.token, body: { points: ivanTrack.slice(0, 100) } });
  assert.equal(again.body.saved, 0, "повторная отправка ничего не дублирует");
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: olegTrack } });
  assert.equal((await call("POST", "/v1/tracks", { token: anna.token, body: { points: [[1, 2]] } })).status, 400);

  const last = await call("GET", "/v1/tracks/last", { token: ivan.token });
  assert.ok(Math.abs(last.body.last - ivanTrack.at(-1)[0]) < 0.01);

  const day = await call("GET", "/v1/day", { token: anna.token });
  assert.equal(day.status, 200);
  assert.equal(day.body.dayNumber, 1);
  const [first, second, third] = day.body.rows;
  assert.equal(first.name, "Иван");
  assert.equal(first.runs, 2);
  assert.equal(first.speedPlace, 1);
  assert.equal(first.speedPoints, 10);
  assert.equal(first.volumePoints, 10);
  assert.ok(Math.abs(first.topSpeed - 20) < 0.5, `скорость Ивана ${first.topSpeed}`);
  assert.ok(Math.abs(first.vertical - 400) < 30, `перепад Ивана ${first.vertical}`);
  assert.equal(second.name, "Олег");
  assert.equal(second.speedPoints, 7);
  assert.equal(second.speedPoints + second.volumePoints, 14);
  assert.equal(third.name, "Анна");
  assert.equal(third.points, 0);
  assert.equal(third.speedPlace, null);

  const standings = await call("GET", "/v1/standings", { token: oleg.token });
  assert.deepEqual(standings.body.rows.map((row) => [row.name, row.place]), [["Иван", 1], ["Олег", 2], ["Анна", 3]]);

  const live = await call("GET", "/v1/live", { token: anna.token });
  assert.deepEqual(live.body.positions.map((position) => position.name).sort(), ["Иван", "Олег"]);
});

test("короны и автогонки: лучшее время на трассе даёт корону, старт рядом даёт гонку", options, async () => {
  const { readFileSync } = await import("node:fs");
  const trail = JSON.parse(readFileSync(new URL("../config/trails.json", import.meta.url), "utf8")).trails.find((item) => item.number === 28);

  // Спуск точно по линии трассы 28 с постоянной скоростью, точка в секунду, высота падает на 160 м.
  function ride(start, speed) {
    const points = [];
    let t = start;
    const total = trail.length;
    let walked = 0;
    for (let index = 1; index < trail.coords.length; index += 1) {
      const [lat1, lon1] = trail.coords[index - 1];
      const [lat2, lon2] = trail.coords[index];
      const length = Math.hypot((lat2 - lat1) * 111_320, (lon2 - lon1) * 52_456);
      for (let done = 0; done < length; done += speed) {
        const share = done / length;
        points.push([t, lat1 + (lat2 - lat1) * share, lon1 + (lon2 - lon1) * share, 840 - ((walked + done) / total) * 160, speed, 5]);
        t += 1;
      }
      walked += length;
    }
    const [lat, lon] = trail.coords.at(-1);
    points.push([t, lat, lon, 680, speed, 5]);
    return points;
  }

  const today = new Date().toISOString().slice(0, 10);
  const ivan = (await call("POST", "/v1/cups", { body: { cupName: "Короны", name: "Иван", startsOn: today } })).body;
  const oleg = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Олег" } })).body;
  const start = Math.floor(Date.now() / 1000) - 600;
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: ride(start, 12) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: ride(start + 10, 15) } });

  const crowns = await call("GET", "/v1/crowns", { token: ivan.token });
  assert.equal(crowns.status, 200);
  const crown = crowns.body.trails.find((item) => item.number === 28);
  assert.equal(crown.holder.name, "Олег");
  assert.ok(crown.mine > crown.holder.seconds, `Иван ${crown.mine} c, Олег ${crown.holder.seconds} c`);
  assert.equal(crowns.body.trails.filter((item) => item.holder).length, 1, "другие трассы не засчитаны");

  const day = await call("GET", "/v1/day", { token: ivan.token });
  const [first, second] = day.body.rows;
  assert.equal(first.name, "Олег");
  assert.equal(first.crowns, 1);
  assert.equal(first.crownPoints, 2);
  assert.equal(first.raceWins, 1);
  assert.equal(first.racePoints, 1);
  assert.equal(second.crowns, 0);
  assert.equal(second.raceWins, 0);
  assert.equal(first.points, first.speedPoints + first.volumePoints + 3);
});

test("территория: трек вдали от курорта в зачёт не идёт, пока её не выключить", options, async () => {
  const today = new Date().toISOString().slice(0, 10);
  const admin = (await call("POST", "/v1/cups", { body: { cupName: "Дома", name: "Иван", startsOn: today } })).body;
  const start = Math.floor(Date.now() / 1000) - 1500;
  // Тот же круг, но сдвинутый на 300 км к югу.
  const far = lap(start, { peakSpeed: 15 }).map(([t, lat, ...rest]) => [t, lat - 2.7, ...rest]);
  await call("POST", "/v1/tracks", { token: admin.token, body: { points: far } });

  assert.equal((await call("GET", "/v1/day", { token: admin.token })).body.rows[0].runs, 0);
  await call("PATCH", "/v1/cup", { token: admin.token, body: { geofence: false } });
  assert.equal((await call("GET", "/v1/day", { token: admin.token })).body.rows[0].runs, 1);
});
