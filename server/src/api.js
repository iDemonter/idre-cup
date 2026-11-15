// API игры: кубок, участники, треки, итоги дня, общий зачёт.
// Телефон подписывает запросы токеном устройства: Authorization: Bearer <токен>.
// В базе лежит только хеш токена.

import { createHash, randomBytes, randomInt } from "node:crypto";
import express from "express";
import { analyze, meters } from "./analyzer.js";
import { scoreDay } from "./scoring.js";
import { loadTrails, matchRun, toMeters } from "./trails.js";

const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // без похожих O/0 и I/1
const MAX_BATCH = 5000;

class ApiError extends Error {
  constructor(status, code, message) {
    super(message ?? code);
    this.status = status;
    this.code = code;
  }
}

const hashToken = (token) => createHash("sha256").update(token).digest("hex");
const newToken = () => randomBytes(32).toString("base64url");
const newCode = () => Array.from({ length: 6 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join("");

function cleanName(value, field = "name") {
  if (typeof value !== "string") throw new ApiError(400, "bad_request", `Нужно поле ${field}`);
  const name = value.trim().replace(/\s+/g, " ");
  if (name.length < 1 || name.length > 24) throw new ApiError(400, "bad_name", "Имя: от 1 до 24 символов");
  return name;
}

function cleanDate(value) {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value))) {
    throw new ApiError(400, "bad_date", "Дата в виде 2027-01-03");
  }
  return value;
}

function cupJson(row) {
  return {
    id: row.id,
    name: row.name,
    code: row.invite_code,
    startsOn: row.starts_on,
    days: row.days,
    prize: row.prize,
    timezone: row.timezone,
    geofence: row.geofence,
    home: row.home_lat === null || row.home_lon === null ? null : { lat: row.home_lat, lon: row.home_lon },
  };
}

// avatar: номер версии картинки или null, если аватара нет. Сама картинка: GET /v1/participants/:id/avatar.
const personJson = (row) => ({ id: row.id, name: row.name, isAdmin: row.is_admin, avatar: row.avatar ?? null });
const PERSON_COLUMNS = "id, name, is_admin, case when avatar is null then null else avatar_version end as avatar";

// Даты из Postgres приходят строками 2027-01-03, а не объектами Date: так не съезжает часовой пояс.
const CUP_COLUMNS =
  "id, name, invite_code, to_char(starts_on, 'YYYY-MM-DD') as starts_on, days, prize, timezone, geofence, home_lat, home_lon";

/**
 * @param {import("express").Express} app
 * @param {{ db: import("pg").Pool, rules: object, attemptLimit?: number }} options
 */
export function mountApi(app, { db, rules, attemptLimit = 30, autoEvents = true }) {
  const trackRules = {
    holdSeconds: rules.day.speedHoldSeconds,
    reversal: rules.track.reversalMeters,
    minVertical: rules.track.minVerticalMeters,
    gap: rules.track.gapSeconds,
    movingSpeed: rules.track.movingSpeed,
  };
  const resort = { lat: rules.resort.lat, lon: rules.resort.lon };
  const trails = loadTrails(resort);

  // --- Защита от перебора кодов: не больше attemptLimit (30) попыток создать или войти за 10 минут с одного адреса.
  const attempts = new Map();
  function limit(req) {
    const forwarded = req.headers["cf-connecting-ip"] ?? req.headers["x-forwarded-for"];
    const address = (Array.isArray(forwarded) ? forwarded[0] : forwarded)?.split(",")[0].trim() ?? req.socket.remoteAddress ?? "?";
    const now = Date.now();
    const recent = (attempts.get(address) ?? []).filter((time) => now - time < 600_000);
    if (recent.length >= attemptLimit) throw new ApiError(429, "too_many_requests", "Слишком много попыток, подождите 10 минут");
    recent.push(now);
    attempts.set(address, recent);
    if (attempts.size > 5000) attempts.clear();
  }

  // --- Кто спрашивает.
  async function auth(req, _res, next) {
    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    if (!token) throw new ApiError(401, "no_token", "Нужен токен устройства");
    const found = await db.query(
      `select cup_id, ${PERSON_COLUMNS} from participants where device_token_hash = $1 and removed_at is null`,
      [hashToken(token)],
    );
    if (found.rows.length === 0) throw new ApiError(401, "bad_token", "Участник не найден или удалён");
    req.me = found.rows[0];
    next();
  }

  function adminOnly(req) {
    if (!req.me.is_admin) throw new ApiError(403, "admin_only", "Это может только админ кубка");
  }

  async function loadCup(cupId) {
    const cup = await db.query(`select ${CUP_COLUMNS} from cups where id = $1`, [cupId]);
    return cup.rows[0];
  }

  async function loadPeople(cupId) {
    const people = await db.query(
      `select ${PERSON_COLUMNS} from participants where cup_id = $1 and removed_at is null order by joined_at`,
      [cupId],
    );
    return people.rows;
  }

  async function uniqueCode() {
    for (let attempt = 0; attempt < 20; attempt += 1) {
      const code = newCode();
      const taken = await db.query("select 1 from cups where invite_code = $1", [code]);
      if (taken.rows.length === 0) return code;
    }
    throw new ApiError(500, "no_code", "Не удалось подобрать код");
  }

  // --- Кубок: создать.
  app.post("/v1/cups", async (req, res) => {
    limit(req);
    const cupName = cleanName(req.body?.cupName, "cupName");
    const name = cleanName(req.body?.name);
    const startsOn = cleanDate(req.body?.startsOn);
    const prize = typeof req.body?.prize === "string" ? req.body.prize.trim().slice(0, 120) || null : null;
    const geofence = req.body?.geofence !== false;
    const token = newToken();
    const code = await uniqueCode();

    const client = await db.connect();
    try {
      await client.query("begin");
      const cup = await client.query(
        `insert into cups (name, invite_code, starts_on, days, prize, geofence) values ($1, $2, $3, $4, $5, $6) returning ${CUP_COLUMNS}`,
        [cupName, code, startsOn, rules.days, prize, geofence],
      );
      const me = await client.query(
        `insert into participants (cup_id, name, is_admin, device_token_hash) values ($1, $2, true, $3) returning ${PERSON_COLUMNS}`,
        [cup.rows[0].id, name, hashToken(token)],
      );
      await client.query("commit");
      res.status(201).json({ cup: cupJson(cup.rows[0]), me: personJson(me.rows[0]), token });
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  });

  // --- Кубок: войти по коду.
  app.post("/v1/join", async (req, res) => {
    limit(req);
    const name = cleanName(req.body?.name);
    const code = typeof req.body?.code === "string" ? req.body.code.trim().toUpperCase() : "";
    const cup = await db.query(`select ${CUP_COLUMNS} from cups where invite_code = $1`, [code]);
    if (cup.rows.length === 0) throw new ApiError(404, "no_cup", "Кубка с таким кодом нет");

    const people = await loadPeople(cup.rows[0].id);
    if (people.length >= rules.maxParticipants) throw new ApiError(409, "cup_full", "В кубке уже нет мест");
    if (people.some((person) => person.name.toLowerCase() === name.toLowerCase())) {
      throw new ApiError(409, "name_taken", "Такое имя в кубке уже есть");
    }
    const token = newToken();
    const me = await db.query(
      `insert into participants (cup_id, name, device_token_hash) values ($1, $2, $3) returning ${PERSON_COLUMNS}`,
      [cup.rows[0].id, name, hashToken(token)],
    );
    res.status(201).json({ cup: cupJson(cup.rows[0]), me: personJson(me.rows[0]), token });
  });

  // --- Код возврата: участник (или админ за него) получает одноразовый код на сутки.
  app.post("/v1/participants/:id/restore", auth, async (req, res) => {
    const person = await findPerson(req);
    if (person.id !== req.me.id) adminOnly(req);
    const code = Array.from({ length: 8 }, () => CODE_ALPHABET[randomInt(CODE_ALPHABET.length)]).join("");
    await db.query(
      "update participants set restore_code_hash = $1, restore_expires = now() + interval '24 hours' where id = $2",
      [hashToken(code), person.id],
    );
    res.json({ code, name: person.name, hours: 24 });
  });

  // --- Вход по коду возврата: новый телефон получает токен, старый перестаёт работать.
  app.post("/v1/restore", async (req, res) => {
    limit(req);
    const code = typeof req.body?.code === "string" ? req.body.code.trim().toUpperCase() : "";
    const token = newToken();
    const restored = await db.query(
      `update participants set device_token_hash = $1, restore_code_hash = null, restore_expires = null
       where restore_code_hash = $2 and restore_expires > now() and removed_at is null
       returning cup_id, ${PERSON_COLUMNS}`,
      [hashToken(token), code.length === 8 ? hashToken(code) : ""],
    );
    if (restored.rows.length === 0) throw new ApiError(404, "no_restore", "Код возврата не подошёл или истёк");
    const cup = await loadCup(restored.rows[0].cup_id);
    res.json({ cup: cupJson(cup), me: personJson(restored.rows[0]), token });
  });

  // --- Я, мой кубок и участники.
  app.get("/v1/me", auth, async (req, res) => {
    const [cup, people] = await Promise.all([loadCup(req.me.cup_id), loadPeople(req.me.cup_id)]);
    res.json({ cup: cupJson(cup), me: personJson(req.me), participants: people.map(personJson) });
  });

  // --- Настройки кубка. Жильё может поставить любой участник, остальное меняет админ.
  app.patch("/v1/cup", auth, async (req, res) => {
    const body = req.body ?? {};
    const sets = [];
    const values = [];
    const set = (column, value) => {
      values.push(value);
      sets.push(`${column} = $${values.length}`);
    };

    if ("home" in body) {
      if (body.home === null) {
        set("home_lat", null);
        set("home_lon", null);
      } else {
        const { lat, lon } = body.home ?? {};
        if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
          throw new ApiError(400, "bad_home", "Жильё: нужны lat и lon");
        }
        set("home_lat", lat);
        set("home_lon", lon);
      }
    }
    const adminFields = ["name", "startsOn", "prize", "geofence"].filter((field) => field in body);
    if (adminFields.length > 0) adminOnly(req);
    if ("name" in body) set("name", cleanName(body.name));
    if ("startsOn" in body) set("starts_on", cleanDate(body.startsOn));
    if ("prize" in body) set("prize", typeof body.prize === "string" ? body.prize.trim().slice(0, 120) || null : null);
    if ("geofence" in body) set("geofence", body.geofence !== false);
    if (sets.length === 0) throw new ApiError(400, "bad_request", "Нечего менять");

    values.push(req.me.cup_id);
    const cup = await db.query(`update cups set ${sets.join(", ")} where id = $${values.length} returning ${CUP_COLUMNS}`, values);
    statsCache.clear(); // могла смениться территория или дата начала
    res.json({ cup: cupJson(cup.rows[0]) });
  });

  // --- Новый код приглашения (старый перестаёт работать).
  app.post("/v1/cup/code", auth, async (req, res) => {
    adminOnly(req);
    const code = await uniqueCode();
    const cup = await db.query(`update cups set invite_code = $1 where id = $2 returning ${CUP_COLUMNS}`, [code, req.me.cup_id]);
    res.json({ cup: cupJson(cup.rows[0]) });
  });

  async function findPerson(req) {
    const person = await db.query(
      `select ${PERSON_COLUMNS} from participants where id = $1 and cup_id = $2 and removed_at is null`,
      [req.params.id, req.me.cup_id],
    );
    if (person.rows.length === 0) throw new ApiError(404, "no_participant", "Такого участника в кубке нет");
    return person.rows[0];
  }

  const isUuid = (value) => /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  app.param("id", (_req, _res, next, value) => {
    next(isUuid(value) ? undefined : new ApiError(404, "no_participant", "Такого участника в кубке нет"));
  });

  // --- Переименовать: себя может каждый, других только админ.
  app.patch("/v1/participants/:id", auth, async (req, res) => {
    const person = await findPerson(req);
    if (person.id !== req.me.id) adminOnly(req);
    const name = cleanName(req.body?.name);
    const people = await loadPeople(req.me.cup_id);
    if (people.some((other) => other.id !== person.id && other.name.toLowerCase() === name.toLowerCase())) {
      throw new ApiError(409, "name_taken", "Такое имя в кубке уже есть");
    }
    const updated = await db.query(`update participants set name = $1 where id = $2 returning ${PERSON_COLUMNS}`, [name, person.id]);
    res.json({ participant: personJson(updated.rows[0]) });
  });

  // --- Удалить участника. Его треки остаются в базе, но в зачёт он больше не попадает.
  app.delete("/v1/participants/:id", auth, async (req, res) => {
    adminOnly(req);
    const person = await findPerson(req);
    if (person.id === req.me.id) throw new ApiError(409, "self_remove", "Сначала передайте права админа");
    await db.query("update participants set removed_at = now() where id = $1", [person.id]);
    res.json({ ok: true });
  });

  // --- Передать права админа.
  app.post("/v1/participants/:id/admin", auth, async (req, res) => {
    adminOnly(req);
    const person = await findPerson(req);
    const client = await db.connect();
    try {
      await client.query("begin");
      await client.query("update participants set is_admin = false where cup_id = $1", [req.me.cup_id]);
      await client.query("update participants set is_admin = true where id = $1", [person.id]);
      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
    res.json({ ok: true });
  });

  // --- Аватар: телефон присылает готовую маленькую картинку (JPEG или PNG, до 300 КБ).
  const imageType = (bytes) => {
    if (bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8) return "image/jpeg";
    if (bytes.length > 8 && bytes.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47]))) return "image/png";
    return null;
  };

  app.put("/v1/me/avatar", auth, express.raw({ type: ["image/jpeg", "image/png"], limit: "300kb" }), async (req, res) => {
    if (!Buffer.isBuffer(req.body) || !imageType(req.body)) throw new ApiError(400, "bad_image", "Нужна картинка JPEG или PNG");
    const updated = await db.query(
      "update participants set avatar = $1, avatar_version = avatar_version + 1 where id = $2 returning avatar_version",
      [req.body, req.me.id],
    );
    res.json({ avatar: updated.rows[0].avatar_version });
  });

  app.delete("/v1/me/avatar", auth, async (req, res) => {
    await db.query("update participants set avatar = null, avatar_version = avatar_version + 1 where id = $1", [req.me.id]);
    res.json({ avatar: null });
  });

  // Картинку видят только участники того же кубка. Адрес с ?v=версия можно кешировать навсегда.
  app.get("/v1/participants/:id/avatar", auth, async (req, res) => {
    const found = await db.query(
      "select avatar from participants where id = $1 and cup_id = $2 and removed_at is null and avatar is not null",
      [req.params.id, req.me.cup_id],
    );
    if (found.rows.length === 0) throw new ApiError(404, "no_avatar", "Аватара нет");
    const bytes = found.rows[0].avatar;
    res.set("Content-Type", imageType(bytes) ?? "application/octet-stream");
    res.set("Cache-Control", "private, max-age=31536000, immutable");
    res.send(bytes);
  });

  // --- Треки: телефон присылает точки пачками. Повторная отправка тех же точек безвредна.
  app.post("/v1/tracks", auth, async (req, res) => {
    const points = req.body?.points;
    if (!Array.isArray(points) || points.length === 0) throw new ApiError(400, "bad_request", "Нужен массив points");
    if (points.length > MAX_BATCH) throw new ApiError(413, "too_many_points", `Не больше ${MAX_BATCH} точек за раз`);

    const now = Date.now() / 1000;
    const columns = { t: [], lat: [], lon: [], alt: [], speed: [], acc: [] };
    for (const point of points) {
      if (!Array.isArray(point) || point.length < 6 || !point.slice(0, 6).every(Number.isFinite)) {
        throw new ApiError(400, "bad_point", "Точка: [время, широта, долгота, высота, скорость, точность]");
      }
      const [t, lat, lon, alt, speed, acc] = point;
      if (Math.abs(lat) > 90 || Math.abs(lon) > 180) throw new ApiError(400, "bad_point", "Широта или долгота вне диапазона");
      if (t > now + 86_400 || t < now - 60 * 86_400) continue; // часы телефона сбиты или точка слишком старая
      columns.t.push(t);
      columns.lat.push(lat);
      columns.lon.push(lon);
      columns.alt.push(alt);
      columns.speed.push(speed);
      columns.acc.push(acc);
    }

    let saved = 0;
    if (columns.t.length > 0) {
      const inserted = await db.query(
        `insert into track_points (participant_id, ts, lat, lon, altitude_m, speed_mps, h_accuracy_m)
         select $1, to_timestamp(u.t), u.lat, u.lon, u.alt, u.speed, u.acc
         from unnest($2::double precision[], $3::double precision[], $4::double precision[], $5::real[], $6::real[], $7::real[])
           as u(t, lat, lon, alt, speed, acc)
         on conflict do nothing`,
        [req.me.id, columns.t, columns.lat, columns.lon, columns.alt, columns.speed, columns.acc],
      );
      saved = inserted.rowCount;
    }
    const last = await db.query("select extract(epoch from max(ts))::float8 as last from track_points where participant_id = $1", [req.me.id]);
    res.json({ received: points.length, saved, last: last.rows[0].last });
  });

  // --- До какого времени сервер уже знает мой трек (после переустановки телефон шлёт только новое).
  app.get("/v1/tracks/last", auth, async (req, res) => {
    const last = await db.query("select extract(epoch from max(ts))::float8 as last from track_points where participant_id = $1", [req.me.id]);
    res.json({ last: last.rows[0].last });
  });

  const statsCache = new Map();

  // --- Итоги по набору точек: скорость, перепад, спуски и пройденные трассы.
  function summarize(rows, cup) {
    // Вне территории курорта точки в зачёт не идут (кроме кубков с выключенной территорией).
    const points = cup.geofence ? rows.filter((point) => meters(resort, point) <= rules.resort.radiusKm * 1000) : rows;
    const full = analyze(points, trackRules);
    // Какие трассы пройдены на каждом спуске и за сколько: для корон, автогонок и дуэлей.
    const trailRuns = [];
    for (const segment of full.segments) {
      if (segment.kind !== "run") continue;
      const run = points
        .filter((point) => point.t >= segment.start - 20 && point.t <= segment.end + 5)
        .map((point) => {
          const [x, y] = toMeters(resort, point.lat, point.lon);
          return { t: point.t, x, y };
        });
      trailRuns.push(...matchRun(run, trails));
    }
    return {
      topSpeed: full.topSpeed,
      vertical: Math.round(full.vertical),
      runs: full.runs,
      distance: Math.round(full.runDistance),
      trailRuns,
    };
  }

  const POINT_COLUMNS =
    "extract(epoch from ts)::float8 as t, lat, lon, coalesce(altitude_m, 0)::float8 as alt, coalesce(speed_mps, -1)::float8 as speed";

  // --- Итоги участника за отрезок времени (секунды с 1970): по ним считаются дуэли.
  async function rangeStats(participantId, from, to, cup) {
    const range = "ts >= to_timestamp($2) and ts <= to_timestamp($3)";
    const mark = await db.query(
      `select count(*)::int as count, extract(epoch from max(ts))::float8 as last from track_points where participant_id = $1 and ${range}`,
      [participantId, from, to],
    );
    const key = `${participantId}|${from}|${to}|${cup.geofence}`;
    const cached = statsCache.get(key);
    if (cached && cached.count === mark.rows[0].count && cached.last === mark.rows[0].last) return cached.stats;
    const loaded = await db.query(
      `select ${POINT_COLUMNS} from track_points where participant_id = $1 and ${range} order by ts`,
      [participantId, from, to],
    );
    const stats = summarize(loaded.rows, cup);
    statsCache.set(key, { count: mark.rows[0].count, last: mark.rows[0].last, stats });
    if (statsCache.size > 2000) statsCache.delete(statsCache.keys().next().value);
    return stats;
  }

  // --- Итоги дня участника по его треку. Пересчитываются, только когда пришли новые точки.
  async function dayStats(participantId, date, cup) {
    const range = `ts >= ($2::date::timestamp at time zone $3) and ts < (($2::date + 1)::timestamp at time zone $3)`;
    const mark = await db.query(
      `select count(*)::int as count, extract(epoch from max(ts))::float8 as last from track_points where participant_id = $1 and ${range}`,
      [participantId, date, cup.timezone],
    );
    const key = `${participantId}|${date}|${cup.geofence}`;
    const cached = statsCache.get(key);
    if (cached && cached.count === mark.rows[0].count && cached.last === mark.rows[0].last) return cached.stats;

    const loaded = await db.query(
      `select ${POINT_COLUMNS} from track_points where participant_id = $1 and ${range} order by ts`,
      [participantId, date, cup.timezone],
    );
    const stats = summarize(loaded.rows, cup);
    statsCache.set(key, { count: mark.rows[0].count, last: mark.rows[0].last, stats });
    if (statsCache.size > 2000) statsCache.delete(statsCache.keys().next().value);
    return stats;
  }

  async function today(cup) {
    const now = await db.query("select to_char((now() at time zone $1)::date, 'YYYY-MM-DD') as date", [cup.timezone]);
    return now.rows[0].date;
  }

  const addDays = (date, days) => new Date(Date.parse(`${date}T00:00:00Z`) + days * 86_400_000).toISOString().slice(0, 10);
  const daysBetween = (from, to) => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000);

  /** Номер дня кубка (с 1) и множитель очков. Вне дат кубка: день без номера, множитель 1. */
  function dayInfo(cup, date) {
    if (!cup.starts_on) return { dayNumber: null, multiplier: 1 };
    const number = daysBetween(cup.starts_on, date) + 1;
    if (number < 1 || number > cup.days) return { dayNumber: null, multiplier: 1 };
    return { dayNumber: number, multiplier: number === cup.days ? rules.lastDayMultiplier : 1 };
  }

  /** Дни, которые идут в зачёт на дату until включительно. */
  async function countedDates(cup, people, until) {
    if (cup.starts_on) {
      const count = Math.min(cup.days, daysBetween(cup.starts_on, until) + 1);
      return Array.from({ length: Math.max(count, 0) }, (_, index) => addDays(cup.starts_on, index));
    }
    const found = await db.query(
      `select distinct to_char((ts at time zone $2)::date, 'YYYY-MM-DD') as date
       from track_points where participant_id = any($1::uuid[]) and (ts at time zone $2)::date <= $3::date
       order by date desc limit 14`,
      [people.map((person) => person.id), cup.timezone, until],
    );
    return found.rows.map((row) => row.date).reverse();
  }

  /**
   * Лучшие времена на трассах за зачётные дни до даты until включительно.
   * holders: трасса → { id, seconds, at } (король), personal: участник → (трасса → секунды).
   */
  async function bestTimes(cup, people, until) {
    const holders = new Map();
    const personal = new Map(people.map((person) => [person.id, new Map()]));
    for (const date of await countedDates(cup, people, until)) {
      for (const person of people) {
        for (const run of (await dayStats(person.id, date, cup)).trailRuns) {
          const mine = personal.get(person.id);
          if (!mine.has(run.number) || run.seconds < mine.get(run.number)) mine.set(run.number, run.seconds);
          const best = holders.get(run.number);
          // При равном времени король тот, кто проехал раньше.
          if (!best || run.seconds < best.seconds || (run.seconds === best.seconds && run.end < best.at)) {
            holders.set(run.number, { id: person.id, seconds: run.seconds, at: run.end });
          }
        }
      }
    }
    return { holders, personal };
  }

  // --- Дуэли один на один. Вызов → ответ → отрезок времени → итог по трекам обоих.
  const duelRules = rules.duel;
  const DUEL_KINDS = ["race", "speed", "endurance"];
  const DUEL_COLUMNS = `id, cup_id, challenger_id, opponent_id, kind, trail, minutes, stake, status,
    extract(epoch from created_at)::float8 as created_at, extract(epoch from starts_at)::float8 as starts_at,
    extract(epoch from ends_at)::float8 as ends_at, winner_id, challenger_value, opponent_value`;
  const trailNames = new Map(trails.map((trail) => [trail.number, trail.name]));

  async function serverNow() {
    const now = await db.query("select extract(epoch from now())::float8 as now");
    return now.rows[0].now;
  }

  /** Что сравнивается: гонка = секунды на трассе (меньше лучше), скорость = м/с, выносливость = метры перепада. */
  function duelValue(duel, stats) {
    if (duel.kind === "race") {
      const times = stats.trailRuns.filter((run) => run.number === duel.trail).map((run) => run.seconds);
      return times.length > 0 ? Math.min(...times) : null;
    }
    if (stats.runs === 0) return null;
    return duel.kind === "speed" ? Math.round(stats.topSpeed * 36) / 36 : stats.vertical;
  }

  async function duelValues(duel, cup) {
    const [challenger, opponent] = await Promise.all(
      [duel.challenger_id, duel.opponent_id].map((id) => rangeStats(id, duel.starts_at, duel.ends_at, cup)),
    );
    return [duelValue(duel, challenger), duelValue(duel, opponent)];
  }

  /** Победитель или null при ничьей. Кто не показал результата, проигрывает тому, кто показал. */
  function duelWinner(duel, challenger, opponent) {
    if (challenger === null && opponent === null) return null;
    if (challenger === null) return duel.opponent_id;
    if (opponent === null) return duel.challenger_id;
    if (challenger === opponent) return null;
    const challengerWins = duel.kind === "race" ? challenger < opponent : challenger > opponent;
    return challengerWins ? duel.challenger_id : duel.opponent_id;
  }

  /** Двигает дуэли кубка: вызовы без ответа гаснут, закончившиеся получают итог. */
  async function refreshDuels(cup) {
    await db.query(
      "update duels set status = 'expired' where cup_id = $1 and status = 'pending' and created_at < now() - make_interval(mins => $2)",
      [cup.id, duelRules.answerMinutes],
    );
    const due = await db.query(
      `select ${DUEL_COLUMNS} from duels where cup_id = $1 and status = 'active' and ends_at < now() - make_interval(secs => $2)`,
      [cup.id, duelRules.settleDelaySeconds],
    );
    if (due.rows.length === 0) return;
    const now = await serverNow();
    for (const duel of due.rows) {
      // Телефон мог быть без связи: ждём, пока от обоих придут точки позже конца дуэли, но не дольше waitForTracksMinutes.
      const lasts = await db.query(
        `select participant_id, extract(epoch from max(ts))::float8 as last from track_points
         where participant_id = any($1::uuid[]) group by participant_id`,
        [[duel.challenger_id, duel.opponent_id]],
      );
      const seen = new Map(lasts.rows.map((row) => [row.participant_id, row.last]));
      const complete = [duel.challenger_id, duel.opponent_id].every((id) => (seen.get(id) ?? 0) >= duel.ends_at);
      if (!complete && now < duel.ends_at + duelRules.waitForTracksMinutes * 60) continue;
      const [challenger, opponent] = await duelValues(duel, cup);
      await db.query(
        `update duels set status = 'finished', winner_id = $2, challenger_value = $3, opponent_value = $4, settled_at = now()
         where id = $1 and status = 'active'`,
        [duel.id, duelWinner(duel, challenger, opponent), challenger, opponent],
      );
    }
  }

  /** Сколько дуэлей (идущих и законченных) у участника сегодня и сколько из них с этим соперником. */
  async function duelCounts(cup, personId, otherId) {
    const found = await db.query(
      `select count(*)::int as total,
              count(*) filter (where challenger_id = $3 or opponent_id = $3)::int as pair
       from duels
       where cup_id = $1 and status in ('active', 'finished') and (challenger_id = $2 or opponent_id = $2)
         and (starts_at at time zone $4)::date = (now() at time zone $4)::date`,
      [cup.id, personId, otherId, cup.timezone],
    );
    return found.rows[0];
  }

  async function checkDuelLimits(cup, me, other, otherName) {
    const mine = await duelCounts(cup, me, other);
    if (mine.total >= duelRules.perDayLimit) {
      throw new ApiError(409, "duel_limit", `На сегодня дуэли закончились: не больше ${duelRules.perDayLimit} в день`);
    }
    if (mine.pair >= duelRules.perPairPerDay) throw new ApiError(409, "duel_pair", `С ${otherName} сегодня уже была дуэль`);
    const theirs = await duelCounts(cup, other, me);
    if (theirs.total >= duelRules.perDayLimit) throw new ApiError(409, "duel_limit", `У ${otherName} на сегодня дуэли закончились`);
  }

  function duelJson(duel, names, now, live) {
    const value = (side) => (live ? live[side] : duel[`${side}_value`]);
    const person = (side) => ({ id: duel[`${side}_id`], name: names.get(duel[`${side}_id`]) ?? "?", value: value(side) ?? null });
    return {
      id: duel.id,
      kind: duel.kind,
      trail: duel.trail === null ? null : { number: duel.trail, name: trailNames.get(duel.trail) ?? "" },
      minutes: duel.minutes,
      stake: duel.stake,
      // counting: время вышло, сервер ждёт остаток треков и считает итог.
      status: duel.status === "active" && now > duel.ends_at ? "counting" : duel.status,
      createdAt: duel.created_at,
      answerBy: duel.status === "pending" ? duel.created_at + duelRules.answerMinutes * 60 : null,
      startsAt: duel.starts_at,
      endsAt: duel.ends_at,
      challenger: person("challenger"),
      opponent: person("opponent"),
      winner: duel.winner_id,
    };
  }

  async function duelNames(cupId) {
    // С удалёнными участниками: их имена остаются в истории дуэлей.
    const found = await db.query("select id, name from participants where cup_id = $1", [cupId]);
    return new Map(found.rows.map((row) => [row.id, row.name]));
  }

  async function oneDuel(cup, id) {
    const [found, names, now] = await Promise.all([
      db.query(`select ${DUEL_COLUMNS} from duels where id = $1 and cup_id = $2`, [id, cup.id]),
      duelNames(cup.id),
      serverNow(),
    ]);
    return duelJson(found.rows[0], names, now, null);
  }

  // --- Дуэли кубка: свежие сверху, у идущих сразу текущие результаты.
  app.get("/v1/duels", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    await refreshDuels(cup);
    const [found, names, now, mine] = await Promise.all([
      db.query(`select ${DUEL_COLUMNS} from duels where cup_id = $1 order by created_at desc limit 40`, [cup.id]),
      duelNames(cup.id),
      serverNow(),
      duelCounts(cup, req.me.id, req.me.id),
    ]);
    const duels = [];
    for (const duel of found.rows) {
      let live = null;
      if (duel.status === "active") {
        const [challenger, opponent] = await duelValues(duel, cup);
        live = { challenger, opponent };
      }
      duels.push(duelJson(duel, names, now, live));
    }
    res.json({
      now,
      stake: duelRules.stake,
      answerMinutes: duelRules.answerMinutes,
      minutes: duelRules.minutes,
      left: Math.max(0, duelRules.perDayLimit - mine.total),
      duels,
    });
  });

  // --- Вызвать на дуэль.
  app.post("/v1/duels", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    const body = req.body ?? {};
    const kind = body.kind;
    if (!DUEL_KINDS.includes(kind)) throw new ApiError(400, "bad_duel", "Вид дуэли: race, speed или endurance");
    if (!duelRules.minutes[kind].includes(body.minutes)) {
      throw new ApiError(400, "bad_duel", `Время дуэли: ${duelRules.minutes[kind].join(" или ")} минут`);
    }
    let trail = null;
    if (kind === "race") {
      if (!trailNames.has(body.trail)) throw new ApiError(400, "bad_duel", "Для гонки нужна зачётная трасса");
      trail = body.trail;
    }
    if (typeof body.opponent !== "string" || !isUuid(body.opponent) || body.opponent === req.me.id) {
      throw new ApiError(400, "bad_duel", "Нужен соперник из кубка");
    }
    const opponent = await db.query(
      `select ${PERSON_COLUMNS} from participants where id = $1 and cup_id = $2 and removed_at is null`,
      [body.opponent, cup.id],
    );
    if (opponent.rows.length === 0) throw new ApiError(404, "no_participant", "Такого участника в кубке нет");
    const other = opponent.rows[0];

    await refreshDuels(cup);
    const busy = await db.query(
      `select challenger_id, opponent_id from duels
       where cup_id = $1 and status in ('pending', 'active')
         and (challenger_id = any($2::uuid[]) or opponent_id = any($2::uuid[]))`,
      [cup.id, [req.me.id, other.id]],
    );
    if (busy.rows.some((row) => row.challenger_id === req.me.id || row.opponent_id === req.me.id)) {
      throw new ApiError(409, "duel_busy", "Сначала закончи свою дуэль или дождись ответа на вызов");
    }
    if (busy.rows.length > 0) throw new ApiError(409, "duel_busy", `${other.name} сейчас в другой дуэли`);
    await checkDuelLimits(cup, req.me.id, other.id, other.name);

    const created = await db.query(
      `insert into duels (cup_id, challenger_id, opponent_id, kind, trail, minutes, stake)
       values ($1, $2, $3, $4, $5, $6, $7) returning id`,
      [cup.id, req.me.id, other.id, kind, trail, body.minutes, duelRules.stake],
    );
    res.status(201).json({ duel: await oneDuel(cup, created.rows[0].id) });
  });

  // --- Ответ на вызов: принять (время пошло), отказаться или отозвать свой вызов. Отказ ничего не стоит.
  app.post("/v1/duels/:duel/:action", auth, async (req, res) => {
    const { duel: id, action } = req.params;
    if (!isUuid(id) || !["accept", "decline", "cancel"].includes(action)) throw new ApiError(404, "no_duel", "Такой дуэли нет");
    const cup = await loadCup(req.me.cup_id);
    await refreshDuels(cup);
    const found = await db.query(`select ${DUEL_COLUMNS} from duels where id = $1 and cup_id = $2`, [id, cup.id]);
    const duel = found.rows[0];
    if (!duel) throw new ApiError(404, "no_duel", "Такой дуэли нет");
    if (duel.status !== "pending") throw new ApiError(409, "duel_closed", "На этот вызов уже ответили или он истёк");

    if (action === "cancel") {
      if (duel.challenger_id !== req.me.id) throw new ApiError(403, "not_yours", "Отозвать вызов может только тот, кто его бросил");
      await db.query("update duels set status = 'cancelled' where id = $1 and status = 'pending'", [id]);
    } else {
      if (duel.opponent_id !== req.me.id) throw new ApiError(403, "not_yours", "Ответить может только тот, кого вызвали");
      if (action === "decline") {
        await db.query("update duels set status = 'declined' where id = $1 and status = 'pending'", [id]);
      } else {
        const names = await duelNames(cup.id);
        await checkDuelLimits(cup, req.me.id, duel.challenger_id, names.get(duel.challenger_id) ?? "соперником");
        await db.query(
          `update duels set status = 'active', starts_at = now(), ends_at = now() + make_interval(mins => minutes)
           where id = $1 and status = 'pending'`,
          [id],
        );
      }
    }
    res.json({ duel: await oneDuel(cup, id) });
  });

  /** Очки дуэлей за день: победитель забирает ставку у проигравшего. День дуэли = день её начала. */
  async function duelPoints(cup, people, date) {
    const found = await db.query(
      `select challenger_id, opponent_id, winner_id, stake from duels
       where cup_id = $1 and status = 'finished' and winner_id is not null
         and (starts_at at time zone $2)::date = $3::date`,
      [cup.id, cup.timezone, date],
    );
    const inCup = new Set(people.map((person) => person.id));
    const result = new Map();
    const add = (id, points, won) => {
      const row = result.get(id) ?? { points: 0, wins: 0, losses: 0 };
      row.points += points;
      if (won) row.wins += 1;
      else row.losses += 1;
      result.set(id, row);
    };
    for (const duel of found.rows) {
      if (!inCup.has(duel.challenger_id) || !inCup.has(duel.opponent_id)) continue;
      const loser = duel.winner_id === duel.challenger_id ? duel.opponent_id : duel.challenger_id;
      add(duel.winner_id, duel.stake, true);
      add(loser, -duel.stake, false);
    }
    return result;
  }

  // --- События дня: короткие задания для всего кубка. Сервер сам выбирает время и вид.
  const eventRules = rules.events;
  const EVENT_KINDS = Object.keys(eventRules.kinds);
  const EVENT_COLUMNS = `id, cup_id, to_char(day, 'YYYY-MM-DD') as day, slot, kind, status,
    extract(epoch from starts_at)::float8 as starts_at, extract(epoch from ends_at)::float8 as ends_at, leader_id, results`;
  const clockMinutes = (text) => {
    const [hours, minutes] = text.split(":").map(Number);
    return hours * 60 + minutes;
  };
  const roundSpeed = (speed) => Math.round(speed * 36) / 36;

  /** Идёт ли день в зачёт: у кубка с датами только его дни, без дат любой день. */
  const isCupDay = (cup, date) => !cup.starts_on || dayInfo(cup, date).dayNumber !== null;

  /** Начало дня кубка, секунды с 1970. */
  async function dayStart(cup, date) {
    const found = await db.query("select extract(epoch from ($1::date::timestamp at time zone $2))::float8 as t", [date, cup.timezone]);
    return found.rows[0].t;
  }

  /** Расписание событий на день: 2–3 случайных момента в светлое окно, не ближе часа друг к другу. */
  async function planEvents(cup, date) {
    const planned = await db.query("select 1 from events where cup_id = $1 and day = $2 and slot is not null limit 1", [cup.id, date]);
    if (planned.rows.length > 0) return;
    const from = clockMinutes(eventRules.windowFrom);
    const longest = Math.max(...EVENT_KINDS.map((kind) => eventRules.kinds[kind].minutes));
    const to = clockMinutes(eventRules.windowTo) - longest;
    const count = eventRules.perDayMin + randomInt(eventRules.perDayMax - eventRules.perDayMin + 1);
    const spaced = (times) => times.every((time, index) => index === 0 || time - times[index - 1] >= eventRules.minGapMinutes);
    let times = [];
    for (let attempt = 0; attempt < 200 && (times.length === 0 || !spaced(times)); attempt += 1) {
      times = Array.from({ length: count }, () => from + randomInt(to - from + 1)).sort((a, b) => a - b);
    }
    if (!spaced(times)) times = Array.from({ length: count }, (_, index) => Math.round(from + ((to - from) * (index + 0.5)) / count));
    for (const [index, minutes] of times.entries()) {
      await db.query(
        `insert into events (cup_id, day, slot, starts_at)
         values ($1, $2::date, $3, ($2::date::timestamp + make_interval(mins => $4)) at time zone $5)
         on conflict do nothing`,
        [cup.id, date, index + 1, minutes, cup.timezone],
      );
    }
  }

  /** Что было у участников до начала события: лучшая скорость дня и уже пройденные трассы. */
  async function eventBaseline(cup, people, event) {
    const start = await dayStart(cup, event.day);
    const earlierDays = await bestTimes(cup, people, addDays(event.day, -1));
    const speed = new Map();
    const visited = new Map();
    for (const person of people) {
      const earlier = await rangeStats(person.id, start, event.starts_at - 0.001, cup);
      speed.set(person.id, earlier.runs > 0 ? earlier.topSpeed : 0);
      const seen = new Set(earlierDays.personal.get(person.id)?.keys() ?? []);
      for (const run of earlier.trailRuns) seen.add(run.number);
      visited.set(person.id, seen);
    }
    return { speed, visited };
  }

  /**
   * Ход события по каждому участнику. value: что показал за время события, goal: что надо превзойти, done: задание выполнено.
   * double: метры перепада, которые пошли в объём дважды. best и hunt: скорость, м/с. explore: номер новой трассы.
   */
  async function eventEntries(cup, people, event) {
    const windows = await Promise.all(people.map((person) => rangeStats(person.id, event.starts_at, event.ends_at, cup)));
    const speedOf = (stats) => (stats.runs > 0 ? roundSpeed(stats.topSpeed) : null);
    if (event.kind === "double") {
      return people.map((person, index) => ({
        id: person.id,
        name: person.name,
        value: windows[index].runs > 0 ? windows[index].vertical : null,
        goal: null,
        done: false,
      }));
    }
    if (event.kind === "hunt") {
      const leaderIndex = people.findIndex((person) => person.id === event.leader_id);
      const leaderSpeed = leaderIndex >= 0 ? speedOf(windows[leaderIndex]) : null;
      return people.map((person, index) => {
        const value = speedOf(windows[index]);
        const leader = person.id === event.leader_id;
        return {
          id: person.id,
          name: person.name,
          value,
          goal: leader ? null : leaderSpeed,
          // Лидер без результата проигрывает всем, кто проехал.
          done: !leader && value !== null && (leaderSpeed === null || value > leaderSpeed),
          leader,
        };
      });
    }
    const before = await eventBaseline(cup, people, event);
    if (event.kind === "best") {
      return people.map((person, index) => {
        const value = speedOf(windows[index]);
        const goal = before.speed.get(person.id) > 0 ? roundSpeed(before.speed.get(person.id)) : null;
        return { id: person.id, name: person.name, value, goal, done: goal !== null && value !== null && value > goal };
      });
    }
    return people.map((person, index) => {
      const fresh = windows[index].trailRuns.find((run) => !before.visited.get(person.id).has(run.number));
      return { id: person.id, name: person.name, value: fresh ? fresh.number : null, goal: null, done: Boolean(fresh) };
    });
  }

  /** Кому и сколько очков. Охота: если лидера никто не обогнал, очки получает он сам. */
  function eventAwards(event, entries) {
    const points = eventRules.kinds[event.kind].points ?? 0;
    if (points === 0) return [];
    const winners = entries.filter((entry) => entry.done);
    if (event.kind === "hunt" && winners.length === 0) {
      const leader = entries.find((entry) => entry.leader && entry.value !== null);
      return leader ? [{ id: leader.id, points }] : [];
    }
    return winners.map((entry) => ({ id: entry.id, points }));
  }

  async function standingRows(cup, people, until) {
    const dates = await countedDates(cup, people, until);
    const days = await Promise.all(dates.map((date) => scoredDay(cup, people, date)));
    const rows = people
      .map((person) => {
        const perDay = days.map((day) => day.rows.find((row) => row.id === person.id)?.points ?? 0);
        return { id: person.id, name: person.name, points: perDay.reduce((sum, value) => sum + value, 0), days: perDay };
      })
      .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name, "ru"));
    let place = 0;
    rows.forEach((row, index) => {
      if (index === 0 || row.points < rows[index - 1].points) place = index + 1;
      row.place = place;
    });
    return { dates, rows };
  }

  /** Событие начинается: выбирается вид (тот, что возможен и сегодня ещё не был) и идёт время. */
  async function startEvent(cup, people, event, wanted = null) {
    const standing = await standingRows(cup, people, event.day);
    const leader = standing.rows[0] && standing.rows[0].points > 0 ? standing.rows[0].id : null;
    const ridden = await Promise.all(people.map((person) => dayStats(person.id, event.day, cup)));
    const anyRuns = ridden.some((stats) => stats.runs > 0);
    // Охоте нужен лидер, «побей себя» нужен хотя бы один спуск за сегодня.
    const possible = EVENT_KINDS.filter((kind) => (kind !== "hunt" || leader) && (kind !== "best" || anyRuns));
    let kind = wanted;
    if (wanted) {
      if (!possible.includes(wanted)) throw new ApiError(409, "event_impossible", "Сейчас это событие не запустить: нет лидера или никто ещё не катался");
    } else {
      const used = await db.query("select kind from events where cup_id = $1 and day = $2 and kind is not null", [cup.id, event.day]);
      const usedKinds = new Set(used.rows.map((row) => row.kind));
      const fresh = possible.filter((item) => !usedKinds.has(item));
      const pool = fresh.length > 0 ? fresh : possible;
      kind = pool[randomInt(pool.length)];
    }
    await db.query(
      `update events set kind = $2, status = 'active', starts_at = now(), ends_at = now() + make_interval(mins => $3), leader_id = $4
       where id = $1`,
      [event.id, kind, eventRules.kinds[kind].minutes, kind === "hunt" ? leader : null],
    );
  }

  /** Двигает события кубка: расписание на сегодня, начало (только когда люди катаются), итоги. */
  async function refreshEvents(cup, people) {
    const date = await today(cup);
    if (autoEvents && isCupDay(cup, date)) await planEvents(cup, date);
    const ids = people.map((person) => person.id);

    const due = await db.query(
      `select ${EVENT_COLUMNS} from events where cup_id = $1 and status = 'active' and ends_at < now() - make_interval(secs => $2)`,
      [cup.id, eventRules.settleDelaySeconds],
    );
    const ready = await db.query(
      `select ${EVENT_COLUMNS} from events where cup_id = $1 and status = 'scheduled' and starts_at <= now() order by starts_at`,
      [cup.id],
    );
    if (due.rows.length === 0 && ready.rows.length === 0) return;
    const now = await serverNow();

    for (const event of due.rows) {
      // Кто катался во время события, тот должен успеть прислать трек до его конца; ждём не дольше waitForTracksMinutes.
      const lasts = await db.query(
        `select participant_id, extract(epoch from max(ts))::float8 as last, bool_or(ts <= to_timestamp($3)) as inside
         from track_points where participant_id = any($1::uuid[]) and ts >= to_timestamp($2) group by participant_id`,
        [ids, event.starts_at, event.ends_at],
      );
      const complete = lasts.rows.every((row) => !row.inside || row.last >= event.ends_at);
      if (!complete && now < event.ends_at + eventRules.waitForTracksMinutes * 60) continue;
      const entries = await eventEntries(cup, people, event);
      await db.query("update events set status = 'finished', results = $2, settled_at = now() where id = $1 and status = 'active'", [
        event.id,
        JSON.stringify({ awards: eventAwards(event, entries), entries }),
      ]);
    }

    if (ready.rows.length === 0) return;
    const running = await db.query("select 1 from events where cup_id = $1 and status = 'active' limit 1", [cup.id]);
    let busy = running.rows.length > 0;
    const riders = await db.query(
      `select count(distinct participant_id)::int as count from track_points
       where participant_id = any($1::uuid[]) and ts > now() - make_interval(mins => $2)`,
      [ids, eventRules.riderFreshMinutes],
    );
    const enoughRiders = riders.rows[0].count >= Math.min(eventRules.minRiders, people.length);
    for (const event of ready.rows) {
      const closes = (await dayStart(cup, event.day)) + clockMinutes(eventRules.windowTo) * 60;
      if (now > closes) {
        // Светлое окно кончилось: событие не состоялось.
        await db.query("update events set status = 'skipped' where id = $1", [event.id]);
      } else if (busy || !enoughRiders) {
        // Честно только когда люди на склоне: без катающихся (или пока идёт другое событие) откладываем.
        await db.query("update events set starts_at = now() + make_interval(mins => $2) where id = $1", [event.id, eventRules.postponeMinutes]);
      } else {
        await startEvent(cup, people, event);
        busy = true;
      }
    }
  }

  async function eventJson(cup, people, event, now) {
    const finished = event.status === "finished";
    const entries = finished ? (event.results?.entries ?? []) : await eventEntries(cup, people, event);
    const names = new Map(people.map((person) => [person.id, person.name]));
    return {
      id: event.id,
      kind: event.kind,
      // counting: время вышло, сервер ждёт остаток треков и считает итог.
      status: event.status === "active" && now > event.ends_at ? "counting" : event.status,
      startsAt: event.starts_at,
      endsAt: event.ends_at,
      minutes: eventRules.kinds[event.kind].minutes,
      points: eventRules.kinds[event.kind].points ?? null,
      leader: event.leader_id,
      entries,
      awards: finished ? (event.results?.awards ?? []).map((award) => ({ ...award, name: names.get(award.id) ?? "?" })) : [],
    };
  }

  // --- События сегодня: идущее и законченные. Расписание будущих не раскрывается, только их число.
  app.get("/v1/events", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    const people = await loadPeople(cup.id);
    await refreshEvents(cup, people);
    const date = await today(cup);
    const [found, upcoming, now] = await Promise.all([
      db.query(
        `select ${EVENT_COLUMNS} from events where cup_id = $1 and day = $2 and status in ('active', 'finished') order by starts_at desc`,
        [cup.id, date],
      ),
      db.query("select count(*)::int as count from events where cup_id = $1 and day = $2 and status = 'scheduled'", [cup.id, date]),
      serverNow(),
    ]);
    const events = [];
    for (const event of found.rows) events.push(await eventJson(cup, people, event, now));
    res.json({ now, upcoming: upcoming.rows[0].count, events });
  });

  // --- Запустить событие прямо сейчас: для проверки и для настроения. Только админ.
  app.post("/v1/events", auth, async (req, res) => {
    adminOnly(req);
    const cup = await loadCup(req.me.cup_id);
    const people = await loadPeople(cup.id);
    await refreshEvents(cup, people);
    const kind = req.body?.kind ?? null;
    if (kind !== null && !EVENT_KINDS.includes(kind)) throw new ApiError(400, "bad_event", `Вид события: ${EVENT_KINDS.join(", ")}`);
    const running = await db.query("select 1 from events where cup_id = $1 and status = 'active' limit 1", [cup.id]);
    if (running.rows.length > 0) throw new ApiError(409, "event_busy", "Одно событие уже идёт");
    const created = await db.query(
      `insert into events (cup_id, day, starts_at) values ($1, $2::date, now()) returning ${EVENT_COLUMNS}`,
      [cup.id, await today(cup)],
    );
    try {
      await startEvent(cup, people, created.rows[0], kind);
    } catch (error) {
      await db.query("delete from events where id = $1", [created.rows[0].id]);
      throw error;
    }
    const started = await db.query(`select ${EVENT_COLUMNS} from events where id = $1`, [created.rows[0].id]);
    res.status(201).json({ event: await eventJson(cup, people, started.rows[0], await serverNow()) });
  });

  /** Очки событий за день и прибавка к объёму от «двойного счёта». */
  async function eventEffects(cup, people, date) {
    const found = await db.query(
      `select kind, status, results, extract(epoch from starts_at)::float8 as starts_at, extract(epoch from ends_at)::float8 as ends_at
       from events where cup_id = $1 and day = $2 and status in ('active', 'finished')`,
      [cup.id, date],
    );
    const points = new Map();
    const bonus = new Map();
    for (const event of found.rows) {
      if (event.status === "finished") {
        for (const award of event.results?.awards ?? []) points.set(award.id, (points.get(award.id) ?? 0) + award.points);
      }
      if (event.kind !== "double") continue;
      // Двойной счёт: всё, что проехал за время события, идёт в объём дня ещё раз.
      for (const person of people) {
        const extra = await rangeStats(person.id, event.starts_at, event.ends_at, cup);
        const sum = bonus.get(person.id) ?? { vertical: 0, runs: 0, distance: 0 };
        bonus.set(person.id, { vertical: sum.vertical + extra.vertical, runs: sum.runs + extra.runs, distance: sum.distance + extra.distance });
      }
    }
    return { points, bonus };
  }

  async function scoredDay(cup, people, date) {
    const { dayNumber, multiplier } = dayInfo(cup, date);
    const stats = await Promise.all(people.map((person) => dayStats(person.id, date, cup)));
    const rows = people.map((person, index) => {
      const { trailRuns: _runs, ...numbers } = stats[index];
      return { id: person.id, name: person.name, ...numbers };
    });

    // Короны: кто держит лучшее время на трассе к концу этого дня.
    const { holders } = await bestTimes(cup, people, date);
    const crowns = new Map();
    for (const holder of holders.values()) crowns.set(holder.id, (crowns.get(holder.id) ?? 0) + 1);

    // Автогонки: двое стартовали на одной трассе почти одновременно, побеждает меньшее время.
    const wins = new Map();
    const starts = people.flatMap((person, index) => stats[index].trailRuns.map((run) => ({ ...run, id: person.id })));
    for (let a = 0; a < starts.length; a += 1) {
      for (let b = a + 1; b < starts.length; b += 1) {
        const one = starts[a];
        const two = starts[b];
        if (one.id === two.id || one.number !== two.number) continue;
        if (Math.abs(one.start - two.start) > rules.crowns.autoRaceStartWindowSeconds || one.seconds === two.seconds) continue;
        const winner = one.seconds < two.seconds ? one.id : two.id;
        wins.set(winner, (wins.get(winner) ?? 0) + 1);
      }
    }

    // Дуэли: ставка переходит от проигравшего к победителю и на последнем дне не удваивается.
    const duels = await duelPoints(cup, people, date);

    // События: очки за задания и «двойной счёт» в объёме. Места считаются с прибавкой, цифры в строке остаются настоящими.
    const effects = await eventEffects(cup, people, date);
    const boosted = rows.map((row) => {
      const extra = effects.bonus.get(row.id);
      return extra ? { ...row, vertical: row.vertical + extra.vertical, runs: row.runs + extra.runs, distance: row.distance + extra.distance } : row;
    });
    const raw = new Map(rows.map((row) => [row.id, row]));

    const scored = scoreDay(boosted, rules, multiplier).map((row) => {
      const { vertical, runs, distance } = raw.get(row.id);
      const eventPoints = (effects.points.get(row.id) ?? 0) * multiplier;
      row = { ...row, vertical, runs, distance, bonusVertical: effects.bonus.get(row.id)?.vertical ?? 0, eventPoints, points: row.points + eventPoints };
      const crownCount = crowns.get(row.id) ?? 0;
      const raceWins = wins.get(row.id) ?? 0;
      const crownPoints = crownCount * rules.crowns.pointsPerCrownAtDayEnd * multiplier;
      const racePoints = raceWins * rules.crowns.autoRaceWinPoints * multiplier;
      const duel = duels.get(row.id) ?? { points: 0, wins: 0, losses: 0 };
      return {
        ...row,
        crowns: crownCount,
        crownPoints,
        raceWins,
        racePoints,
        duelWins: duel.wins,
        duelLosses: duel.losses,
        duelPoints: duel.points,
        points: row.points + crownPoints + racePoints + duel.points,
      };
    });
    scored.sort((a, b) => b.points - a.points || b.topSpeed - a.topSpeed || a.name.localeCompare(b.name, "ru"));
    return { date, dayNumber, multiplier, rows: scored };
  }

  // --- Рейтинг дня.
  app.get("/v1/day", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    const date = cleanDate(req.query.date) ?? (await today(cup));
    const people = await loadPeople(cup.id);
    await refreshDuels(cup);
    await refreshEvents(cup, people);
    res.json(await scoredDay(cup, people, date));
  });

  // --- Общий зачёт: сумма очков по дням кубка. Пока даты не заданы, в зачёт идут все дни с треками.
  app.get("/v1/standings", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    const people = await loadPeople(cup.id);
    const now = await today(cup);
    await refreshDuels(cup);
    await refreshEvents(cup, people);
    const { dates, rows } = await standingRows(cup, people, now);
    res.json({ today: now, dates, rows });
  });

  // --- Короны: лучшее время на каждой зачётной трассе, король и мой результат.
  app.get("/v1/crowns", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    const people = await loadPeople(cup.id);
    const { holders, personal } = await bestTimes(cup, people, await today(cup));
    const names = new Map(people.map((person) => [person.id, person.name]));
    const mine = personal.get(req.me.id) ?? new Map();
    res.json({
      trails: trails.map((trail) => {
        const holder = holders.get(trail.number);
        return {
          number: trail.number,
          name: trail.name,
          holder: holder ? { id: holder.id, name: names.get(holder.id), seconds: holder.seconds } : null,
          mine: mine.get(trail.number) ?? null,
        };
      }),
    });
  });

  // --- Где сейчас участники: последняя точка каждого за 15 минут.
  app.get("/v1/live", auth, async (req, res) => {
    const people = await loadPeople(req.me.cup_id);
    const found = await db.query(
      `select distinct on (participant_id) participant_id, extract(epoch from ts)::float8 as t, lat, lon
       from track_points
       where participant_id = any($1::uuid[]) and ts > now() - interval '15 minutes'
       order by participant_id, ts desc`,
      [people.map((person) => person.id)],
    );
    const names = new Map(people.map((person) => [person.id, person.name]));
    res.json({
      positions: found.rows.map((row) => ({ id: row.participant_id, name: names.get(row.participant_id), t: row.t, lat: row.lat, lon: row.lon })),
    });
  });
}

export { ApiError };
