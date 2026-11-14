import assert from "node:assert/strict";
import { after, before, test } from "node:test";
import { createApp } from "../src/app.js";

let server;
let base;

before(async () => {
  const app = createApp({ db: { query: async () => ({ rows: [] }) }, version: "test" });
  await new Promise((resolve) => {
    server = app.listen(0, resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => {
  server.close();
});

test("health отвечает и видит базу", async () => {
  const res = await fetch(`${base}/health`);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.db, true);
  assert.equal(body.version, "test");
});

test("health без базы сообщает db: false", async () => {
  const app = createApp({ db: null });
  const s = await new Promise((resolve) => {
    const srv = app.listen(0, () => resolve(srv));
  });
  const res = await fetch(`http://127.0.0.1:${s.address().port}/health`);
  const body = await res.json();
  s.close();
  assert.equal(body.db, false);
});

test("config отдаёт правила из спецификации", async () => {
  const res = await fetch(`${base}/v1/config`);
  assert.equal(res.status, 200);
  const rules = await res.json();
  assert.deepEqual(rules.day.speedPoints, [10, 7, 5, 3, 1]);
  assert.deepEqual(rules.day.volumePoints, [10, 7, 5, 3, 1]);
  assert.equal(rules.duel.stake, 5);
  assert.equal(rules.lastDayMultiplier, 2);
  assert.equal(rules.maxParticipants, 8);
});

test("неизвестный адрес даёт 404", async () => {
  const res = await fetch(`${base}/nope`);
  assert.equal(res.status, 404);
});
