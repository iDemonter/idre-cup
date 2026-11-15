// API игры: кубок, участники, треки, итоги дня, общий зачёт.
// Телефон подписывает запросы токеном устройства: Authorization: Bearer <токен>.
// В базе лежит только хеш токена.

import { createHash, randomBytes, randomInt } from "node:crypto";
import express from "express";
import { analyze, meters } from "./analyzer.js";
import { scoreDay } from "./scoring.js";

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
 * @param {{ db: import("pg").Pool, rules: object }} options
 */
export function mountApi(app, { db, rules }) {
  const trackRules = {
    holdSeconds: rules.day.speedHoldSeconds,
    reversal: rules.track.reversalMeters,
    minVertical: rules.track.minVerticalMeters,
    gap: rules.track.gapSeconds,
    movingSpeed: rules.track.movingSpeed,
  };
  const resort = { lat: rules.resort.lat, lon: rules.resort.lon };

  // --- Защита от перебора кодов: не больше 30 попыток создать или войти за 10 минут с одного адреса.
  const attempts = new Map();
  function limit(req) {
    const forwarded = req.headers["cf-connecting-ip"] ?? req.headers["x-forwarded-for"];
    const address = (Array.isArray(forwarded) ? forwarded[0] : forwarded)?.split(",")[0].trim() ?? req.socket.remoteAddress ?? "?";
    const now = Date.now();
    const recent = (attempts.get(address) ?? []).filter((time) => now - time < 600_000);
    if (recent.length >= 30) throw new ApiError(429, "too_many_requests", "Слишком много попыток, подождите 10 минут");
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

  // --- Итоги дня участника по его треку. Пересчитываются, только когда пришли новые точки.
  const statsCache = new Map();
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
      `select extract(epoch from ts)::float8 as t, lat, lon, coalesce(altitude_m, 0)::float8 as alt, coalesce(speed_mps, -1)::float8 as speed
       from track_points where participant_id = $1 and ${range} order by ts`,
      [participantId, date, cup.timezone],
    );
    // Вне территории курорта точки в зачёт не идут (кроме кубков с выключенной территорией).
    const points = cup.geofence
      ? loaded.rows.filter((point) => meters(resort, point) <= rules.resort.radiusKm * 1000)
      : loaded.rows;
    const full = analyze(points, trackRules);
    const stats = {
      topSpeed: full.topSpeed,
      vertical: Math.round(full.vertical),
      runs: full.runs,
      distance: Math.round(full.runDistance),
    };
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

  async function scoredDay(cup, people, date) {
    const { dayNumber, multiplier } = dayInfo(cup, date);
    const rows = await Promise.all(
      people.map(async (person) => ({ id: person.id, name: person.name, ...(await dayStats(person.id, date, cup)) })),
    );
    return { date, dayNumber, multiplier, rows: scoreDay(rows, rules, multiplier) };
  }

  // --- Рейтинг дня.
  app.get("/v1/day", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    const date = cleanDate(req.query.date) ?? (await today(cup));
    const people = await loadPeople(cup.id);
    res.json(await scoredDay(cup, people, date));
  });

  // --- Общий зачёт: сумма очков по дням кубка. Пока даты не заданы, в зачёт идут все дни с треками.
  app.get("/v1/standings", auth, async (req, res) => {
    const cup = await loadCup(req.me.cup_id);
    const people = await loadPeople(cup.id);
    const now = await today(cup);

    let dates;
    if (cup.starts_on) {
      const count = Math.min(cup.days, daysBetween(cup.starts_on, now) + 1);
      dates = Array.from({ length: Math.max(count, 0) }, (_, index) => addDays(cup.starts_on, index));
    } else {
      const found = await db.query(
        `select distinct to_char((ts at time zone $2)::date, 'YYYY-MM-DD') as date
         from track_points where participant_id = any($1::uuid[]) order by date desc limit 14`,
        [people.map((person) => person.id), cup.timezone],
      );
      dates = found.rows.map((row) => row.date).reverse();
    }

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
    res.json({ today: now, dates, rows });
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
