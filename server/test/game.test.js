// Полный сценарий на настоящей базе: кубок, вход, треки, рейтинг.
// Нужен Postgres: TEST_DATABASE_URL=postgres://user:pass@host/db npm test
// Без этой переменной тесты пропускаются.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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

// Спуск точно по линии трассы с постоянной скоростью, точка в секунду, высота падает на 160 м.
const trailList = JSON.parse(readFileSync(new URL("../config/trails.json", import.meta.url), "utf8")).trails;
function trailRide(number, start, speed) {
  const trail = trailList.find((item) => item.number === number);
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

before(async () => {
  if (!url) return;
  db = new pg.Pool({ connectionString: url, max: 5 });
  await db.query("drop table if exists games, events, duels, track_points, participants, cups, schema_migrations cascade");
  await migrate(db, () => {});
  const app = createApp({ db, version: "test", attemptLimit: 1000, autoEvents: false });
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
  const ride = (start, speed) => trailRide(28, start, speed);

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

test("дуэли: вызов, ответ, итог по трекам, 5 очков переходят победителю", options, async () => {
  const today = new Date().toISOString().slice(0, 10);
  const ivan = (await call("POST", "/v1/cups", { body: { cupName: "Дуэли", name: "Иван", startsOn: today } })).body;
  const oleg = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Олег" } })).body;
  const anna = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Анна" } })).body;
  // Сдвигает время дуэли: настоящей дуэли нужен час, тесту секунды.
  const shift = (id, from, to) =>
    db.query("update duels set starts_at = now() - make_interval(secs => $2), ends_at = now() - make_interval(secs => $3) where id = $1", [id, from, to]);

  // Неверные вызовы.
  const bad = (body) => call("POST", "/v1/duels", { token: ivan.token, body });
  assert.equal((await bad({ opponent: oleg.me.id, kind: "race", minutes: 60 })).status, 400, "гонка без трассы");
  assert.equal((await bad({ opponent: oleg.me.id, kind: "speed", minutes: 45 })).status, 400, "нет такого времени");
  assert.equal((await bad({ opponent: ivan.me.id, kind: "speed", minutes: 30 })).status, 400, "сам с собой");

  // Вызов и ответ.
  const challenge = await bad({ opponent: oleg.me.id, kind: "race", trail: 28, minutes: 60 });
  assert.equal(challenge.status, 201);
  assert.equal(challenge.body.duel.status, "pending");
  assert.equal(challenge.body.duel.trail.number, 28);
  const id = challenge.body.duel.id;
  assert.equal((await bad({ opponent: anna.me.id, kind: "speed", minutes: 30 })).body.error, "duel_busy");
  const third = await call("POST", "/v1/duels", { token: anna.token, body: { opponent: oleg.me.id, kind: "speed", minutes: 30 } });
  assert.equal(third.body.error, "duel_busy");
  assert.equal((await call("POST", `/v1/duels/${id}/accept`, { token: anna.token })).status, 403);
  const accepted = await call("POST", `/v1/duels/${id}/accept`, { token: oleg.token });
  assert.equal(accepted.body.duel.status, "active");
  assert.ok(Math.abs(accepted.body.duel.endsAt - accepted.body.duel.startsAt - 3600) < 1);
  assert.equal((await call("POST", `/v1/duels/${id}/decline`, { token: oleg.token })).status, 409, "уже принято");

  // Оба проехали трассу 25 минут назад: Олег быстрее.
  const start = Math.floor(Date.now() / 1000) - 1500;
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: trailRide(28, start, 12) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: trailRide(28, start + 100, 15) } });

  await shift(id, 3000, -600);
  let list = await call("GET", "/v1/duels", { token: anna.token });
  let duel = list.body.duels.find((item) => item.id === id);
  assert.equal(duel.status, "active");
  assert.ok(duel.challenger.value > duel.opponent.value, `Иван ${duel.challenger.value} c, Олег ${duel.opponent.value} c`);

  // Время вышло, но треки могли дойти не все: сервер ждёт.
  await shift(id, 3000, 100);
  list = await call("GET", "/v1/duels", { token: ivan.token });
  assert.equal(list.body.duels.find((item) => item.id === id).status, "counting");

  // Ждать больше нечего: итог.
  await shift(id, 3000, 960);
  list = await call("GET", "/v1/duels", { token: ivan.token });
  duel = list.body.duels.find((item) => item.id === id);
  assert.equal(duel.status, "finished");
  assert.equal(duel.winner, oleg.me.id);
  assert.equal(list.body.left, 2);

  let day = (await call("GET", "/v1/day", { token: ivan.token })).body.rows;
  const row = (name) => day.find((item) => item.name === name);
  assert.equal(row("Олег").duelPoints, 5);
  assert.equal(row("Олег").duelWins, 1);
  assert.equal(row("Иван").duelPoints, -5);
  assert.equal(row("Иван").points, row("Иван").speedPoints + row("Иван").volumePoints + row("Иван").crownPoints + row("Иван").racePoints - 5);

  // Второй раз за день с тем же соперником нельзя.
  assert.equal((await bad({ opponent: oleg.me.id, kind: "speed", minutes: 30 })).body.error, "duel_pair");

  // Отказ и отзыв вызова ничего не стоят.
  const declined = await bad({ opponent: anna.me.id, kind: "endurance", minutes: 60 });
  assert.equal((await call("POST", `/v1/duels/${declined.body.duel.id}/decline`, { token: anna.token })).body.duel.status, "declined");
  const cancelled = await bad({ opponent: anna.me.id, kind: "endurance", minutes: 60 });
  assert.equal((await call("POST", `/v1/duels/${cancelled.body.duel.id}/cancel`, { token: anna.token })).status, 403);
  assert.equal((await call("POST", `/v1/duels/${cancelled.body.duel.id}/cancel`, { token: ivan.token })).body.duel.status, "cancelled");

  // Скорость: Анна вызвала Ивана и не каталась. Кто без результата, проигрывает.
  const speed = await call("POST", "/v1/duels", { token: anna.token, body: { opponent: ivan.me.id, kind: "speed", minutes: 30 } });
  await call("POST", `/v1/duels/${speed.body.duel.id}/accept`, { token: ivan.token });
  await shift(speed.body.duel.id, 3000, 960);
  list = await call("GET", "/v1/duels", { token: anna.token });
  duel = list.body.duels.find((item) => item.id === speed.body.duel.id);
  assert.equal(duel.status, "finished");
  assert.equal(duel.winner, ivan.me.id);
  assert.equal(duel.challenger.value, null);
  assert.ok(Math.abs(duel.opponent.value - 12) < 0.5, `скорость Ивана ${duel.opponent.value}`);

  day = (await call("GET", "/v1/day", { token: anna.token })).body.rows;
  assert.equal(row("Иван").duelPoints, 0);
  assert.equal(row("Анна").duelPoints, -5);
  assert.equal(row("Анна").points, -5);
  const standings = (await call("GET", "/v1/standings", { token: anna.token })).body.rows;
  assert.equal(standings.find((item) => item.name === "Анна").points, -5);
});

test("события: новая трасса, побей себя, охота на лидера, двойной счёт", options, async () => {
  const today = new Date().toISOString().slice(0, 10);
  const ivan = (await call("POST", "/v1/cups", { body: { cupName: "События", name: "Иван", startsOn: today } })).body;
  const oleg = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Олег" } })).body;
  const anna = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Анна" } })).body;
  const shift = (id, from, to) =>
    db.query("update events set starts_at = now() - make_interval(secs => $2), ends_at = now() - make_interval(secs => $3) where id = $1", [id, from, to]);
  const start = (kind) => call("POST", "/v1/events", { token: ivan.token, body: { kind } });
  const events = async (token = ivan.token) => (await call("GET", "/v1/events", { token })).body;
  const entry = (event, person) => event.entries.find((item) => item.id === person.me.id);
  const row = async (name) => (await call("GET", "/v1/day", { token: ivan.token })).body.rows.find((item) => item.name === name);
  const now = Math.floor(Date.now() / 1000);

  assert.equal((await call("POST", "/v1/events", { token: oleg.token, body: { kind: "explore" } })).status, 403, "только админ");
  assert.equal((await start("jump")).status, 400);
  assert.equal((await start("best")).body.error, "event_impossible", "никто ещё не катался");
  assert.equal((await start("hunt")).body.error, "event_impossible", "лидера ещё нет");

  // 50 минут назад: Иван прошёл 28-ю (12 м/с), Олег тоже (11 м/с).
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: trailRide(28, now - 3000, 12) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: trailRide(28, now - 2800, 11) } });
  // 25 минут назад: Иван снова 28-я, но быстрее (15 м/с); Олег впервые 20-я (10 м/с, медленнее своего утра).
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: trailRide(28, now - 1500, 15) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: trailRide(20, now - 1500, 10) } });

  // Новая трасса: окно накрывает вторые спуски. У Олега 20-я новая, у Ивана 28-я уже была.
  const explore = await start("explore");
  assert.equal(explore.status, 201);
  assert.equal(explore.body.event.status, "active");
  assert.equal((await start("double")).body.error, "event_busy");
  await shift(explore.body.event.id, 2000, -300);
  let list = await events(anna.token);
  assert.equal(list.events[0].kind, "explore");
  assert.equal(entry(list.events[0], oleg).done, true);
  assert.equal(entry(list.events[0], oleg).value, 20);
  assert.equal(entry(list.events[0], ivan).done, false);
  await shift(explore.body.event.id, 2000, 1000);
  list = await events();
  assert.equal(list.events[0].status, "finished");
  assert.deepEqual(list.events[0].awards.map((award) => [award.name, award.points]), [["Олег", 3]]);
  assert.equal((await row("Олег")).eventPoints, 3);
  assert.equal((await row("Иван")).eventPoints, 0);

  // Побей себя: Иван в окне быстрее своего утра (15 против 12), Олег медленнее (10 против 11).
  const best = await start("best");
  await shift(best.body.event.id, 2000, 1000);
  list = await events();
  const bestEvent = list.events.find((item) => item.id === best.body.event.id);
  assert.equal(bestEvent.status, "finished");
  assert.ok(Math.abs(entry(bestEvent, ivan).goal - 12) < 0.5 && Math.abs(entry(bestEvent, ivan).value - 15) < 0.5);
  assert.deepEqual(bestEvent.awards.map((award) => award.name), ["Иван"]);
  assert.equal(entry(bestEvent, anna).goal, null);

  // Охота на лидера: лидер общего зачёта Иван; в окне он быстрее всех, значит очки ему.
  const hunt = await start("hunt");
  assert.equal(hunt.body.event.leader, ivan.me.id);
  await shift(hunt.body.event.id, 2000, 1000);
  list = await events();
  const huntEvent = list.events.find((item) => item.id === hunt.body.event.id);
  assert.deepEqual(huntEvent.awards.map((award) => [award.name, award.points]), [["Иван", 4]]);
  assert.equal(entry(huntEvent, oleg).done, false);
  assert.equal((await row("Иван")).eventPoints, 7);

  // Двойной счёт: спуск внутри окна идёт в объём дважды, цифры в строке остаются настоящими.
  const before = await row("Олег");
  const double = await start("double");
  await shift(double.body.event.id, 2000, 1000);
  const after = await row("Олег");
  assert.equal(after.vertical, before.vertical);
  assert.ok(after.bonusVertical > 100, `прибавка Олега ${after.bonusVertical}`);
  assert.ok(after.volumeScore >= before.volumeScore);
  assert.equal(after.points, after.speedPoints + after.volumePoints + after.crownPoints + after.racePoints + after.duelPoints + after.eventPoints);

  // Расписание: сервер с включёнными событиями сам назначает 2–3 события на день кубка.
  const auto = createApp({ db, version: "test", attemptLimit: 1000 });
  const listener = await new Promise((resolve) => {
    const started = auto.listen(0, () => resolve(started));
  });
  const reply = await fetch(`http://127.0.0.1:${listener.address().port}/v1/events`, { headers: { authorization: `Bearer ${ivan.token}` } });
  assert.equal(reply.status, 200);
  listener.close();
  const planned = await db.query("select count(*)::int as count from events where cup_id = $1 and slot is not null", [ivan.cup.id]);
  assert.ok(planned.rows[0].count >= 2 && planned.rows[0].count <= 3, `запланировано ${planned.rows[0].count}`);
});

test("джокер и майки: пропущенный день закрывается худшим, майки у единоличных лидеров", options, async () => {
  const start = new Date(Date.now() - 2 * 86_400_000).toISOString().slice(0, 10);
  const ivan = (await call("POST", "/v1/cups", { body: { cupName: "Джокер", name: "Иван", startsOn: start } })).body;
  const oleg = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Олег" } })).body;
  const now = Math.floor(Date.now() / 1000);
  // Позавчера катались оба, вчера только Олег, сегодня оба. Середина дня, чтобы не задеть границы суток.
  const noon = (daysAgo) => now - daysAgo * 86_400;
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: lap(noon(2) - 900, { peakSpeed: 20 }) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: lap(noon(2) - 900, { peakSpeed: 15, east: 200 }) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: lap(noon(1) - 900, { peakSpeed: 15, east: 200 }) } });
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: lap(now - 1000, { peakSpeed: 20 }) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: lap(now - 1000, { peakSpeed: 15, east: 200 }) } });

  const standings = (await call("GET", "/v1/standings", { token: ivan.token })).body;
  const row = (name) => standings.rows.find((item) => item.name === name);
  assert.equal(standings.dates.length, 3);
  assert.equal(row("Иван").joker, 1, "вчерашний пропуск закрыт джокером");
  assert.equal(row("Иван").days[1], Math.min(row("Иван").days[0], row("Иван").days[2]));
  assert.equal(row("Олег").joker, null);
  // Второй день кубка парный, поэтому очки могут сравняться: майка лидера только у единоличного лидера.
  const [top, next] = standings.rows;
  assert.equal(standings.jerseys.leader, top.points > next.points ? top.id : null);
  assert.equal(standings.jerseys.volume, oleg.me.id, "Олег проехал на один круг больше");
  assert.equal(standings.jerseys.crowns, null, "корон ни у кого нет");
});

test("парный день: пары на весь день, бонус лучшей паре, одиночка за двоих", options, async () => {
  // Сегодня второй день кубка: он парный.
  const start = new Date(Date.now() - 86_400_000).toISOString().slice(0, 10);
  const ivan = (await call("POST", "/v1/cups", { body: { cupName: "Пары", name: "Иван", startsOn: start } })).body;
  const others = [];
  for (const name of ["Олег", "Анна"]) others.push((await call("POST", "/v1/join", { body: { code: ivan.cup.code, name } })).body);
  const now = Math.floor(Date.now() / 1000);
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: lap(now - 1000, { peakSpeed: 20 }) } });
  await call("POST", "/v1/tracks", { token: others[0].token, body: { points: lap(now - 1000, { peakSpeed: 15, east: 200 }) } });
  await call("POST", "/v1/tracks", { token: others[1].token, body: { points: lap(now - 1000, { peakSpeed: 12, east: -200 }) } });

  const day = (await call("GET", "/v1/day", { token: ivan.token })).body;
  assert.equal(day.dayNumber, 2);
  assert.equal(day.pairs.length, 2);
  assert.deepEqual(day.pairs.map((pair) => pair.ids.length).sort(), [1, 2]);
  const again = (await call("GET", "/v1/day", { token: ivan.token })).body;
  assert.deepEqual(again.pairs.map((pair) => pair.ids), day.pairs.map((pair) => pair.ids), "пары не меняются");
  const [first, second] = day.pairs;
  assert.ok(first.score >= second.score);
  assert.equal(first.bonus, 6);
  assert.equal(second.bonus, 4);
  for (const row of day.rows) {
    const pair = day.pairs.find((item) => item.ids.includes(row.id));
    assert.equal(row.pairPoints, pair.bonus);
    assert.equal(row.partner ?? null, pair.ids.length === 2 ? pair.names.find((name) => name !== row.name) : null);
  }
  const solo = day.pairs.find((pair) => pair.ids.length === 1);
  const soloRow = day.rows.find((row) => row.id === solo.ids[0]);
  assert.equal(solo.score, 2 * (soloRow.points - soloRow.pairPoints));
  assert.ok(Array.isArray(day.myTrails));
});

test("вечер: «Реакция» и итоги дня", options, async () => {
  const today = new Date().toISOString().slice(0, 10);
  const ivan = (await call("POST", "/v1/cups", { body: { cupName: "Вечер", name: "Иван", startsOn: today } })).body;
  const oleg = (await call("POST", "/v1/join", { body: { code: ivan.cup.code, name: "Олег" } })).body;
  const now = Math.floor(Date.now() / 1000);
  await call("POST", "/v1/tracks", { token: ivan.token, body: { points: trailRide(28, now - 1500, 15) } });
  await call("POST", "/v1/tracks", { token: oleg.token, body: { points: lap(now - 1000, { peakSpeed: 18, east: 200 }) } });

  assert.equal((await call("POST", "/v1/games", { token: oleg.token, body: {} })).status, 403, "только админ");
  const started = await call("POST", "/v1/games", { token: ivan.token, body: {} });
  assert.equal(started.status, 201);
  const game = started.body.game;
  assert.equal(game.delays.length, 3);
  assert.equal((await call("POST", "/v1/games", { token: ivan.token, body: {} })).body.error, "game_busy");

  const send = (token, times) => call("POST", `/v1/games/${game.id}/result`, { token, body: { times } });
  assert.equal((await send(ivan.token, [200, 210])).status, 400);
  assert.equal((await send(ivan.token, [250, 240, null])).status, 200);
  assert.equal((await send(ivan.token, [250, 240, 230])).body.error, "game_closed", "второй раз нельзя");
  const last = await send(oleg.token, [300, 310, 320]);
  assert.equal(last.body.game.status, "finished", "все сыграли");
  const results = last.body.game.results;
  assert.deepEqual(results.map((row) => [row.name, row.place, row.points]), [["Олег", 1, 6], ["Иван", 2, 4]], "фальстарт стоит 1000 мс");

  const day = (await call("GET", "/v1/day", { token: ivan.token })).body.rows;
  assert.equal(day.find((row) => row.name === "Олег").gamePoints, 6);

  const ceremony = (await call("GET", "/v1/ceremony", { token: oleg.token })).body;
  assert.equal(ceremony.fastest.name, "Олег");
  assert.equal(ceremony.crowns.length, 1);
  assert.equal(ceremony.crowns[0].holder, "Иван");
  assert.equal(ceremony.crowns[0].from, null);
  assert.equal(ceremony.games.length, 1);
  assert.ok(ceremony.standings.length === 2);
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
