// Разбор трека на спуски и подъёмы. Тот же алгоритм, что в приложении
// (app/IdreCup/TrackAnalyzer.swift): по нему телефон показывает «Мой день», а сервер считает очки.
//
// Точка: { t: секунды с 1970, lat, lon, alt: м, speed: м/с (меньше нуля = неизвестна) }.

/** Расстояние по земле между двумя точками, м. */
export function meters(a, b) {
  const north = (b.lat - a.lat) * 111_320;
  const east = (b.lon - a.lon) * 111_320 * Math.cos((a.lat * Math.PI) / 180);
  return Math.hypot(north, east);
}

/** Пороги по умолчанию. Сервер подставляет значения из config/rules.json. */
export const standardRules = {
  holdSeconds: 3,
  reversal: 10,
  minVertical: 20,
  gap: 120,
  movingSpeed: 1.5,
};

/**
 * @param {{t:number,lat:number,lon:number,alt:number,speed:number}[]} points по возрастанию времени
 * @returns {{topSpeed:number, vertical:number, runs:number, runDistance:number,
 *            totalDistance:number, movingTime:number, pointCount:number, segments:object[]}}
 */
export function analyze(points, rules = standardRules) {
  const stats = {
    topSpeed: 0,
    vertical: 0,
    runs: 0,
    runDistance: 0,
    totalDistance: 0,
    movingTime: 0,
    pointCount: points.length,
    segments: [],
  };
  const count = points.length;
  if (count < 2) return stats;

  // Шаг от предыдущей точки, скорость, разрывы записи.
  const step = new Float64Array(count);
  const speed = new Float64Array(count);
  const breakBefore = new Uint8Array(count);
  speed[0] = Math.max(points[0].speed, 0);
  for (let i = 1; i < count; i += 1) {
    const seconds = points[i].t - points[i - 1].t;
    if (seconds <= 0 || seconds > rules.gap) {
      breakBefore[i] = 1;
      speed[i] = Math.max(points[i].speed, 0);
      continue;
    }
    const moved = meters(points[i - 1], points[i]);
    step[i] = moved;
    speed[i] = points[i].speed >= 0 ? points[i].speed : moved / seconds;
    stats.totalDistance += moved;
    if (speed[i] >= rules.movingSpeed) stats.movingTime += seconds;
  }

  // Сглаженная высота: среднее по соседним точкам в пределах 10 секунд.
  const height = new Float64Array(count);
  for (let i = 0; i < count; i += 1) {
    let sum = 0;
    let used = 0;
    for (let near = Math.max(0, i - 4); near <= Math.min(count - 1, i + 4); near += 1) {
      if (Math.abs(points[near].t - points[i].t) <= 10) {
        sum += points[near].alt;
        used += 1;
      }
    }
    height[i] = sum / Math.max(used, 1);
  }

  // Развороты высоты. Каждый непрерывный кусок записи даёт свою цепочку.
  const chains = [];
  let chain = [0];
  let direction = 0;
  let extreme = 0;
  for (let i = 1; i < count; i += 1) {
    if (breakBefore[i]) {
      if (chain.at(-1) !== extreme) chain.push(extreme);
      if (chain.at(-1) !== i - 1) chain.push(i - 1);
      chains.push(chain);
      chain = [i];
      direction = 0;
      extreme = i;
      continue;
    }
    if (direction === 0) {
      if (height[i] >= height[extreme] + rules.reversal) {
        direction = 1;
        extreme = i;
      } else if (height[i] <= height[extreme] - rules.reversal) {
        direction = -1;
        extreme = i;
      }
    } else if (direction === 1) {
      if (height[i] > height[extreme]) {
        extreme = i;
      } else if (height[i] <= height[extreme] - rules.reversal) {
        chain.push(extreme);
        direction = -1;
        extreme = i;
      }
    } else if (height[i] < height[extreme]) {
      extreme = i;
    } else if (height[i] >= height[extreme] + rules.reversal) {
      chain.push(extreme);
      direction = 1;
      extreme = i;
    }
  }
  if (chain.at(-1) !== extreme) chain.push(extreme);
  if (chain.at(-1) !== count - 1) chain.push(count - 1);
  chains.push(chain);

  // Участки между разворотами.
  for (const pivots of chains) {
    for (let position = 1; position < pivots.length; position += 1) {
      const from = pivots[position - 1];
      const to = pivots[position];
      if (to <= from) continue;
      const change = height[to] - height[from];
      if (Math.abs(change) < rules.minVertical) continue;

      // Стояние в начале и в конце участка в него не входит.
      let first = from;
      let last = to;
      while (first < last && speed[first + 1] < rules.movingSpeed) first += 1;
      while (last > first && speed[last] < rules.movingSpeed) last -= 1;
      if (last <= first) continue;

      let distance = 0;
      for (let i = first + 1; i <= last; i += 1) distance += step[i];
      stats.segments.push({
        kind: change < 0 ? "run" : "lift",
        start: points[first].t,
        end: points[last].t,
        vertical: Math.abs(change),
        distance,
        topSpeed: heldSpeed(speed, points, first, last, rules.holdSeconds),
      });
    }
  }

  for (const segment of stats.segments) {
    if (segment.kind !== "run") continue;
    stats.runs += 1;
    stats.vertical += segment.vertical;
    stats.runDistance += segment.distance;
    stats.topSpeed = Math.max(stats.topSpeed, segment.topSpeed);
  }
  return stats;
}

/** Наибольшая скорость, которая держалась не меньше hold секунд подряд. */
function heldSpeed(speed, points, from, to, hold) {
  let best = 0;
  let end = from;
  for (let start = from; start <= to; start += 1) {
    if (end < start) end = start;
    while (end < to && points[end].t - points[start].t < hold) end += 1;
    const span = points[end].t - points[start].t;
    if (span < hold) break; // до конца участка осталось меньше hold секунд
    if (span > hold + 3) continue; // дыра в записи, окно не считается
    let lowest = Infinity;
    for (let i = start; i <= end; i += 1) lowest = Math.min(lowest, speed[i]);
    best = Math.max(best, lowest);
  }
  return best;
}
