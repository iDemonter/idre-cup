// Привязка спусков к трассам: по ней считаются короны и автогонки.
//
// Трасса засчитана, если трек прошёл рядом с её верхней точкой, затем рядом с нижней,
// а между ними держался вдоль линии трассы. Время = от верхней точки до нижней.

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const trailsPath = fileURLToPath(new URL("../config/trails.json", import.meta.url));

/** Зачётные участки трасс: [{ number, name, length, line: [[x, y], ...] }], метры от точки отсчёта. */
export function loadTrails(origin) {
  const { trails } = JSON.parse(readFileSync(trailsPath, "utf8"));
  return trails.map((trail) => ({
    number: trail.number,
    name: trail.name,
    length: trail.length,
    line: trail.coords.map(([lat, lon]) => toMeters(origin, lat, lon)),
  }));
}

export function toMeters(origin, lat, lon) {
  return [(lon - origin.lon) * 111_320 * Math.cos((origin.lat * Math.PI) / 180), (lat - origin.lat) * 111_320];
}

function toSegment(point, a, b) {
  const dx = b[0] - a[0];
  const dy = b[1] - a[1];
  const length2 = dx * dx + dy * dy;
  const t = length2 === 0 ? 0 : Math.min(1, Math.max(0, ((point[0] - a[0]) * dx + (point[1] - a[1]) * dy) / length2));
  return Math.hypot(point[0] - (a[0] + dx * t), point[1] - (a[1] + dy * t));
}

function toLine(point, line) {
  let best = Infinity;
  for (let i = 1; i < line.length; i += 1) best = Math.min(best, toSegment(point, line[i - 1], line[i]));
  return best;
}

export const standardGates = {
  gate: 40, // насколько близко к верхней и нижней точке надо пройти, м
  corridor: 45, // «вдоль трассы» = не дальше этого от линии, м
  inside: 0.85, // доля точек в коридоре
  maxSpeed: 45, // быстрее этого в среднем не бывает: сбой GPS, м/с
};

/**
 * @param {{t:number, x:number, y:number}[]} run точки одного спуска по времени
 * @returns {{number:number, start:number, end:number, seconds:number}[]} пройденные трассы
 */
export function matchRun(run, trails, rules = standardGates) {
  const found = [];
  if (run.length < 3) return found;

  for (const trail of trails) {
    const top = trail.line[0];
    const bottom = trail.line.at(-1);

    let startIndex = -1;
    let startGap = rules.gate;
    run.forEach((point, index) => {
      const gap = Math.hypot(point.x - top[0], point.y - top[1]);
      if (gap < startGap) {
        startGap = gap;
        startIndex = index;
      }
    });
    if (startIndex < 0) continue;

    let endIndex = -1;
    let endGap = rules.gate;
    for (let index = startIndex + 1; index < run.length; index += 1) {
      const gap = Math.hypot(run[index].x - bottom[0], run[index].y - bottom[1]);
      if (gap < endGap) {
        endGap = gap;
        endIndex = index;
      }
    }
    if (endIndex < 0) continue;

    const seconds = run[endIndex].t - run[startIndex].t;
    if (seconds < 5 || trail.length / seconds > rules.maxSpeed) continue;

    let inside = 0;
    let sum = 0;
    for (let index = startIndex; index <= endIndex; index += 1) {
      const gap = toLine([run[index].x, run[index].y], trail.line);
      sum += gap;
      if (gap <= rules.corridor) inside += 1;
    }
    const count = endIndex - startIndex + 1;
    if (inside / count < rules.inside) continue;
    found.push({ number: trail.number, start: run[startIndex].t, end: run[endIndex].t, seconds, offset: sum / count });
  }

  // Соседние трассы делят верх и низ: из пересекающихся по времени оставляем ту, к линии которой трек ближе.
  found.sort((a, b) => a.offset - b.offset);
  const kept = [];
  for (const item of found) {
    if (!kept.some((other) => item.start < other.end && other.start < item.end)) kept.push(item);
  }
  return kept
    .sort((a, b) => a.start - b.start)
    .map(({ number, start, end, seconds }) => ({ number, start, end, seconds: Math.round(seconds * 10) / 10 }));
}

/** Номер трассы для людей: у Idre Himmelfjäll в данных номер = 100 + номер с его карты, показываем «H6». */
export function trailLabel(number) {
  return number > 100 ? `H${number - 100}` : String(number);
}
