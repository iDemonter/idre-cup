// Зачёт сезона: каждый катается где хочет, очки копятся весь сезон.
//
// Курорты: Idre Fjäll и Himmelfjäll из config/trails.json (номера как в кубке) и каталог
// config/resorts.json (Åre, Vemdalen, горки Стокгольма; собирает tools/resorts.py из OpenStreetMap).
// Точка трека относится к курорту, если лежит в его круге. Точки вне курортов в сезон не идут.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { analyze, meters } from "./analyzer.js";
import { matchRun, toMeters, trailLabel } from "./trails.js";

const read = (name) => JSON.parse(readFileSync(fileURLToPath(new URL(`../config/${name}`, import.meta.url)), "utf8"));

function prepare(resort, raw) {
  const origin = { lat: resort.lat, lon: resort.lon };
  const trails = [];
  for (const trail of raw) {
    const line = trail.coords.map(([lat, lon]) => toMeters(origin, lat, lon));
    const base = { number: trail.id, length: trail.length, line };
    trails.push(base);
    // Направление линии из OpenStreetMap не всегда сверху вниз: спуск сам покажет, какое верное.
    if (trail.bothWays) trails.push({ ...base, line: [...line].reverse() });
  }
  return { ...resort, origin, match: trails, info: raw.map(({ coords, bothWays, ...rest }) => ({ ...rest, coords })) };
}

/** Все курорты сезона. */
export function loadResorts(rules) {
  const own = read("trails.json").trails;
  const himmel = rules.resort.extraAreas?.[0];
  const idreTrail = (trail) => ({
    id: `idre:${trail.number}`,
    label: trailLabel(trail.number),
    name: trail.name,
    length: trail.length,
    difficulty: null,
    coords: trail.coords,
    bothWays: false,
  });
  const resorts = [
    prepare(
      { id: "idre-fjall", name: "Idre Fjäll", region: "Idre", lat: rules.resort.lat, lon: rules.resort.lon, radiusKm: rules.resort.radiusKm },
      own.filter((trail) => trail.number < 100).map(idreTrail),
    ),
  ];
  if (himmel) {
    resorts.push(
      prepare(
        { id: "idre-himmelfjall", name: "Idre Himmelfjäll", region: "Idre", lat: himmel.lat, lon: himmel.lon, radiusKm: himmel.radiusKm },
        own.filter((trail) => trail.number > 100).map(idreTrail),
      ),
    );
  }
  let catalog = [];
  try {
    catalog = read("resorts.json").resorts;
  } catch {
    catalog = [];
  }
  for (const resort of catalog) {
    resorts.push(
      prepare(
        { id: resort.id, name: resort.name, region: resort.region, lat: resort.center[0], lon: resort.center[1], radiusKm: resort.radiusKm, lifts: resort.lifts },
        resort.trails.map((trail) => ({
          id: trail.id,
          label: trail.ref,
          name: trail.name,
          length: trail.length,
          difficulty: trail.difficulty,
          coords: trail.coords,
          bothWays: true,
        })),
      ),
    );
  }
  return resorts;
}

/** Курорт точки: ближайший (по доле радиуса), в круг которого она попала; иначе null. */
export function resortOf(resorts, point) {
  let best = null;
  let bestShare = 1;
  for (const resort of resorts) {
    const share = meters(resort, point) / (resort.radiusKm * 1000);
    if (share <= bestShare) {
      bestShare = share;
      best = resort;
    }
  }
  return best;
}

/**
 * Сезонный день участника: точки делятся по курортам, на каждом свои спуски и трассы.
 * free = true (пробный кубок): точки вне курортов идут в «другое место» без трасс.
 */
export function seasonDay(points, resorts, trackRules, free = false) {
  const groups = new Map();
  for (const point of points) {
    const resort = resortOf(resorts, point);
    const key = resort?.id ?? (free ? "other" : null);
    if (!key) continue;
    if (!groups.has(key)) groups.set(key, { resort, points: [] });
    groups.get(key).points.push(point);
  }
  const places = [];
  for (const [id, group] of groups) {
    const stats = analyze(group.points, trackRules);
    if (stats.runs === 0) continue;
    const trailRuns = [];
    if (group.resort) {
      for (const segment of stats.segments) {
        if (segment.kind !== "run") continue;
        const run = group.points
          .filter((point) => point.t >= segment.start - 20 && point.t <= segment.end + 5)
          .map((point) => {
            const [x, y] = toMeters(group.resort.origin, point.lat, point.lon);
            return { t: point.t, x, y };
          });
        trailRuns.push(...matchRun(run, group.resort.match).map(({ number, ...rest }) => ({ trail: number, ...rest })));
      }
    }
    places.push({
      resort: id,
      vertical: Math.round(stats.vertical),
      runs: stats.runs,
      topSpeed: stats.topSpeed,
      distance: Math.round(stats.runDistance),
      trailRuns,
    });
  }
  return {
    places,
    vertical: places.reduce((sum, place) => sum + place.vertical, 0),
    runs: places.reduce((sum, place) => sum + place.runs, 0),
    topSpeed: Math.max(0, ...places.map((place) => place.topSpeed)),
  };
}

/**
 * Таблица сезона.
 * @param {{id:string, name:string}[]} people
 * @param {Map<string, {date:string, day:ReturnType<typeof seasonDay>}[]>} days дни каждого участника
 * @param {{dayPoints:number, verticalPer:number, verticalMax:number, meetPoints:number, crownPoints:number}} rules
 */
export function seasonTable(people, days, rules) {
  // Встречи: на одном курорте в один день двое и больше.
  const together = new Map();
  for (const person of people) {
    for (const { date, day } of days.get(person.id) ?? []) {
      for (const place of day.places) {
        if (place.resort === "other") continue;
        const key = `${date}|${place.resort}`;
        if (!together.has(key)) together.set(key, new Set());
        together.get(key).add(person.id);
      }
    }
  }

  // Короны сезона: лучшее время на трассе; при равенстве раньше проехавший.
  const crowns = new Map();
  const personal = new Map();
  for (const person of people) {
    const mine = new Map();
    for (const { day } of days.get(person.id) ?? []) {
      for (const place of day.places) {
        for (const run of place.trailRuns) {
          const holder = crowns.get(run.trail);
          if (!holder || run.seconds < holder.seconds || (run.seconds === holder.seconds && run.start < holder.start)) {
            crowns.set(run.trail, { id: person.id, seconds: run.seconds, start: run.start });
          }
          if (!mine.has(run.trail) || run.seconds < mine.get(run.trail)) mine.set(run.trail, run.seconds);
        }
      }
    }
    personal.set(person.id, mine);
  }
  const crownCount = new Map();
  for (const holder of crowns.values()) crownCount.set(holder.id, (crownCount.get(holder.id) ?? 0) + 1);

  const rows = people.map((person) => {
    const list = (days.get(person.id) ?? []).filter(({ day }) => day.runs > 0);
    let points = 0;
    let meets = 0;
    const resorts = new Set();
    const history = [];
    let bestDay = 0;
    for (const { date, day } of list) {
      const met = day.places.some((place) => (together.get(`${date}|${place.resort}`)?.size ?? 0) > 1);
      const dayPoints =
        rules.dayPoints + Math.min(Math.floor(day.vertical / rules.verticalPer), rules.verticalMax) + (met ? rules.meetPoints : 0);
      points += dayPoints;
      if (met) meets += 1;
      bestDay = Math.max(bestDay, day.vertical);
      for (const place of day.places) resorts.add(place.resort);
      history.push({ date, resorts: day.places.map((place) => place.resort), vertical: day.vertical, runs: day.runs, topSpeed: day.topSpeed, met, points: dayPoints });
    }
    const crownsHeld = crownCount.get(person.id) ?? 0;
    points += crownsHeld * rules.crownPoints;
    return {
      id: person.id,
      name: person.name,
      points,
      days: list.length,
      vertical: list.reduce((sum, { day }) => sum + day.vertical, 0),
      runs: list.reduce((sum, { day }) => sum + day.runs, 0),
      topSpeed: Math.max(0, ...list.map(({ day }) => day.topSpeed)),
      bestDay,
      resorts: [...resorts],
      meets,
      crowns: crownsHeld,
      history: history.reverse(),
    };
  });
  rows.sort((a, b) => b.points - a.points || b.vertical - a.vertical || a.name.localeCompare(b.name, "ru"));
  let place = 0;
  rows.forEach((row, index) => {
    if (index === 0 || row.points !== rows[index - 1].points) place = index + 1;
    row.place = place;
  });
  return { rows, crowns, personal };
}
