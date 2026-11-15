// Места и очки за день по итогам треков. Все числа берутся из config/rules.json.

/**
 * Места с учётом ничьих: при равном результате место одинаковое, следующее пропускается (1, 1, 3).
 * @param {{id:string, value:number}[]} entries только те, у кого есть результат
 * @returns {Map<string, number>} id → место
 */
export function places(entries) {
  const sorted = [...entries].sort((a, b) => b.value - a.value);
  const result = new Map();
  let place = 0;
  let previous = null;
  sorted.forEach((entry, index) => {
    if (previous === null || entry.value < previous) {
      place = index + 1;
      previous = entry.value;
    }
    result.set(entry.id, place);
  });
  return result;
}

/**
 * Объём: перепад, число спусков и дистанция, сведённые в одно число от 0 до 100.
 * Каждая величина берётся как доля от лучшей за день, затем среднее с весами.
 */
export function volumeScores(rows, weights) {
  const best = {
    vertical: Math.max(0, ...rows.map((row) => row.vertical)),
    runs: Math.max(0, ...rows.map((row) => row.runs)),
    distance: Math.max(0, ...rows.map((row) => row.distance)),
  };
  const total = weights.vertical + weights.runs + weights.distance || 1;
  const share = (value, top) => (top > 0 ? value / top : 0);
  return new Map(
    rows.map((row) => [
      row.id,
      (100 *
        (weights.vertical * share(row.vertical, best.vertical) +
          weights.runs * share(row.runs, best.runs) +
          weights.distance * share(row.distance, best.distance))) /
        total,
    ]),
  );
}

/**
 * @param {{id:string, name:string, topSpeed:number, vertical:number, runs:number, distance:number}[]} rows
 * @param {object} rules config/rules.json
 * @param {number} multiplier множитель дня (последний день удваивается)
 */
export function scoreDay(rows, rules, multiplier = 1) {
  const active = rows.filter((row) => row.runs > 0);
  const speedPlaces = places(active.map((row) => ({ id: row.id, value: Math.round(row.topSpeed * 36) / 36 })));
  const volume = volumeScores(active, rules.day.volumeWeights);
  const volumePlaces = places(active.map((row) => ({ id: row.id, value: Math.round(volume.get(row.id) * 10) / 10 })));
  const pointsFor = (table, place) => (place ? (table[place - 1] ?? 0) : 0);

  return rows
    .map((row) => {
      const speedPlace = speedPlaces.get(row.id) ?? null;
      const volumePlace = volumePlaces.get(row.id) ?? null;
      const speedPoints = pointsFor(rules.day.speedPoints, speedPlace) * multiplier;
      const volumePoints = pointsFor(rules.day.volumePoints, volumePlace) * multiplier;
      return {
        ...row,
        volumeScore: Math.round((volume.get(row.id) ?? 0) * 10) / 10,
        speedPlace,
        speedPoints,
        volumePlace,
        volumePoints,
        points: speedPoints + volumePoints,
      };
    })
    .sort((a, b) => b.points - a.points || b.topSpeed - a.topSpeed || a.name.localeCompare(b.name, "ru"));
}
