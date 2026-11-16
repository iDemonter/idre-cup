// Условия на курортах: открытые лифты и трассы, часы работы, погода и снег с сайтов курортов
// (Idre Fjäll, SkiStar) и прогноз MET Norway (yr.no).
//
// Готового API у курортов нет: сервер читает их страницы и разбирает текст. Если курорт переделает сайт,
// разбор вернёт пустые поля, а не упадёт: приложение тогда просто не покажет эту часть.

const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", aring: "å", Aring: "Å", auml: "ä", Auml: "Ä", ouml: "ö", Ouml: "Ö", eacute: "é", ndash: "–", mdash: "—", deg: "°" };

/** HTML → строки текста: теги и скрипты выкинуты, сущности раскрыты, пустые строки убраны. */
export function htmlLines(html) {
  return html
    .replace(/<(script|style|noscript|svg)[\s\S]*?<\/\1>/gi, "\n")
    .replace(/<[^>]+>/g, "\n")
    .split("\n")
    .map((line) =>
      line
        .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
        .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(Number(dec)))
        .replace(/&([a-z]+);/gi, (all, name) => ENTITIES[name] ?? all)
        .replace(/\s+/g, " ")
        .trim(),
    )
    .filter(Boolean);
}

const num = (text) => {
  const found = String(text ?? "").replace(",", ".").match(/-?\d+(\.\d+)?/);
  return found ? Number(found[0]) : null;
};
const after = (lines, label, from = 0) => {
  const index = lines.indexOf(label, from);
  return index < 0 ? null : lines[index + 1];
};
const STATUS = { "öppen": "open", "stängd": "closed", "öppnar senare": "later", "prognos": "later" };
const statusOf = (line) => STATUS[(line ?? "").toLowerCase()] ?? null;

// --- Часы работы: «09.00-17.00», «Mån–tors 09.00-17.00», «Fre–sön 07.00–19.00».
const DAYS = ["sön", "mån", "tis", "ons", "tors", "fre", "lör"];
export function parseHours(line) {
  const time = line.match(/(\d{1,2})[.:](\d{2})\s*[-–]\s*(\d{1,2})[.:](\d{2})/);
  if (!time) return null;
  const pad = (h, m) => `${String(h).padStart(2, "0")}:${m}`;
  const range = line.toLowerCase().match(/(sön|mån|tis|ons|tors|fre|lör)\w*\s*[-–]\s*(sön|mån|tis|ons|tors|fre|lör)/);
  const single = line.toLowerCase().match(/^(?:🕘\s*)?(sön|mån|tis|ons|tors|fre|lör)\w*\s/);
  let days = null;
  if (range) {
    const [from, to] = [DAYS.indexOf(range[1]), DAYS.indexOf(range[2])];
    days = [];
    for (let day = from; ; day = (day + 1) % 7) {
      days.push(day);
      if (day === to) break;
    }
  } else if (single) {
    days = [DAYS.indexOf(single[1])];
  }
  return { opens: pad(time[1], time[2]), closes: pad(time[3], time[4]), days };
}

/** Часы на сегодня (weekday 0 = воскресенье): подходящее правило, иначе правило без дней. */
export function hoursFor(list, weekday) {
  return list.find((hours) => hours.days?.includes(weekday)) ?? list.find((hours) => !hours.days) ?? null;
}

// --- Idre Fjäll: страница «Liftar, backar & spår».
export function parseIdre(lines) {
  const report = lines.indexOf("Driftrapport", lines.indexOf("Driftrapport") + 1);
  const at = report < 0 ? 0 : report;
  const count = (label) => {
    const index = lines.indexOf(label, at);
    return index < 0 ? null : { open: num(lines[index + 1]), total: num(lines[index + 2]) };
  };
  const top = lines.indexOf("Topp", at);
  const valley = lines.indexOf("Dal", top < 0 ? at : top);
  const windAt = lines.indexOf("Vindstyrka & riktning", top);
  const items = [];
  const liftsAt = lines.indexOf("Liftar", at);
  for (let index = liftsAt < 0 ? lines.length : liftsAt; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === "Webbkameror") break;
    const item = line.match(/^([A-ZÅÄÖ]{1,3}|\d{1,3}) - (.+)$/);
    if (!item) continue;
    const hours = [];
    let status = null;
    let comment = null;
    let next = index + 1;
    for (; next < lines.length && next < index + 8; next += 1) {
      const text = lines[next];
      if (/^([A-ZÅÄÖ]{1,3}|\d{1,3}) - /.test(text) || text === "Webbkameror") break;
      const parsed = parseHours(text);
      if (parsed && !status) hours.push(parsed);
      else if (statusOf(text)) status = statusOf(text);
      else if (status && !comment && !/Skipass/.test(text)) comment = text;
    }
    items.push({ code: item[1], name: item[2], status, hours, comment });
    index = next - 1;
  }
  return {
    pistes: count("Öppna pister"),
    lifts: count("Öppna liftar"),
    snow: {
      piste: num(after(lines, "Snödjup (pist)", at)),
      terrain: num(after(lines, "Snödjup (terräng)", at)),
      fresh: num(after(lines, "Snödjup (nysnö)", at)),
    },
    weather: {
      top: top < 0 ? null : { temp: num(after(lines, "Temperatur", top)), wind: windAt < 0 ? null : num(lines[windAt + 1]), gust: windAt < 0 ? null : num(lines[windAt + 2]), direction: windAt < 0 ? null : lines[windAt + 4] ?? null },
      valley: valley < 0 ? null : { temp: num(after(lines, "Temperatur", valley)) },
    },
    liftList: items.filter((item) => /[A-ZÅÄÖ]/.test(item.code)),
  };
}

// --- SkiStar: «SimpleView» одной зоны курорта (Åre by, Högzon, Vemdalsskalet…).
export function parseSkistar(lines) {
  const lifts = [];
  const pistes = [];
  const liftsAt = lines.findIndex((line) => /liftar öppna/.test(line));
  const pistesAt = lines.findIndex((line) => /pister öppna/.test(line));
  const hoursAt = lines.findIndex((line) => /^Öppettider/.test(line));
  const collect = (from, to, into, key) => {
    if (from < 0) return;
    for (let index = from + 1; index < (to < 0 ? lines.length : to); index += 1) {
      const item = lines[index].match(/^(.+), ([\wÅÄÖåäö]+\d*)$/);
      if (!item) continue;
      const status = lines.slice(index + 1, index + 5).map(statusOf).find(Boolean) ?? null;
      into.push({ [key]: item[2], name: item[1], status });
      index += 3;
    }
  };
  collect(liftsAt, pistesAt, lifts, "code");
  collect(pistesAt, hoursAt, pistes, "ref");

  // Часы: «VM8:an (Å22)» → «08:00-16:30», «Övriga öppna liftar» → «09:30-15:00».
  const hours = [];
  if (hoursAt >= 0) {
    for (let index = hoursAt + 1; index < lines.length - 1; index += 1) {
      if (/^Hela säsongens/.test(lines[index])) break;
      const parsed = parseHours(lines[index + 1]);
      if (!parsed) continue;
      const code = lines[index].match(/\(([^)]+)\)/)?.[1] ?? null;
      hours.push({ name: lines[index].replace(/\s*\(.*$/, "").replace(/\*$/, ""), code, ...parsed });
      index += 1;
    }
  }
  const season = hoursAt >= 0 ? lines.slice(hoursAt, hoursAt + 6).find((line) => /\d+ \w+ - \d+ \w+/.test(line)) ?? null : null;

  const top = lines.indexOf("Topp");
  const valley = lines.indexOf("Dal", top < 0 ? 0 : top);
  const block = (from) =>
    from < 0 ? null : { temp: num(lines[from + 1]), wind: num(lines[from + 2]), gust: num(lines[from + 4]) };
  const snowAt = lines.indexOf("Aktuellt snödjup");
  const counts = (at, word) => {
    const found = at < 0 ? null : lines[at].match(/(\d+) av (\d+)/);
    return found ? { open: Number(found[1]), total: Number(found[2]) } : null;
  };
  return {
    lifts: counts(liftsAt, "liftar"),
    pistes: counts(pistesAt, "pister"),
    liftList: lifts,
    pisteList: pistes,
    hours,
    season,
    weather: { top: block(top), valley: block(valley), sky: top > 0 ? lines[top - 1] : null },
    snow:
      snowAt < 0
        ? null
        : {
            terrain: num(after(lines, "Terräng", snowAt)),
            piste: num(after(lines, "Pist", snowAt)),
            last24h: num(after(lines, "Snö senaste 24h", snowAt)),
            last72h: num(after(lines, "Snö senaste 72h", snowAt)),
          },
  };
}

/** Несколько зон SkiStar → один курорт: лифты и трассы вместе, погода и снег с первой зоны. */
export function mergeSkistar(parts) {
  const sum = (key) => {
    const list = parts.map((part) => part[key]).filter(Boolean);
    return list.length ? { open: list.reduce((s, x) => s + x.open, 0), total: list.reduce((s, x) => s + x.total, 0) } : null;
  };
  return {
    lifts: sum("lifts"),
    pistes: sum("pistes"),
    liftList: parts.flatMap((part) => part.liftList),
    pisteList: parts.flatMap((part) => part.pisteList),
    hours: parts.flatMap((part) => part.hours),
    season: parts.find((part) => part.season)?.season ?? null,
    weather: parts.find((part) => part.weather?.top)?.weather ?? null,
    snow: parts.find((part) => part.snow)?.snow ?? null,
  };
}

/** Последний лифт закрывается (без вечерних: позже 20:00 — это вечернее катание). */
export function closingTime(status, weekday) {
  const times = [];
  for (const lift of status.liftList ?? []) {
    if (lift.status === "closed") continue;
    const today = hoursFor(lift.hours ?? [], weekday);
    if (today) times.push(today.closes);
  }
  for (const rule of status.hours ?? []) {
    if (!rule.days || rule.days.includes(weekday)) times.push(rule.closes);
  }
  const day = times.filter((time) => time <= "20:00").sort();
  return day.at(-1) ?? null;
}

// --- Прогноз MET Norway (api.met.no, locationforecast compact): сводка на день и ближайшие часы.
const SYMBOLS = {
  clearsky: "ясно", fair: "малооблачно", partlycloudy: "переменная облачность", cloudy: "облачно", fog: "туман",
  lightsnow: "небольшой снег", snow: "снег", heavysnow: "сильный снег", lightsnowshowers: "снежные заряды", snowshowers: "снежные заряды", heavysnowshowers: "сильные снежные заряды",
  lightsleet: "мокрый снег", sleet: "мокрый снег", heavysleet: "мокрый снег", sleetshowers: "мокрый снег",
  lightrain: "небольшой дождь", rain: "дождь", heavyrain: "сильный дождь", rainshowers: "ливни", lightrainshowers: "небольшой дождь",
};
export const symbolText = (code) => (code ? SYMBOLS[code.replace(/_(day|night|polartwilight)$/, "")] ?? code : null);

/** @param {string} timezone часовой пояс курорта, @param {Date} now */
export function summarizeForecast(json, timezone, now = new Date()) {
  const series = json?.properties?.timeseries ?? [];
  const local = (time) => new Date(time).toLocaleString("sv-SE", { timeZone: timezone, hour12: false });
  const today = local(now).slice(0, 10);
  const hours = series.map((item) => {
    const details = item.data.instant.details;
    const next = item.data.next_1_hours ?? item.data.next_6_hours;
    return {
      time: item.time,
      local: local(item.time),
      temp: details.air_temperature,
      wind: details.wind_speed,
      gust: details.wind_speed_of_gust ?? null,
      symbol: next?.summary?.symbol_code ?? null,
      precipitation: next?.details?.precipitation_amount ?? 0,
    };
  });
  const daytime = hours.filter((hour) => hour.local.slice(0, 10) === today && hour.local.slice(11, 13) >= "09" && hour.local.slice(11, 13) <= "16");
  const pick = daytime.length ? daytime : hours.slice(0, 8);
  if (!pick.length) return null;
  const symbols = pick.map((hour) => hour.symbol).filter(Boolean);
  const common = symbols.sort((a, b) => symbols.filter((x) => x === b).length - symbols.filter((x) => x === a).length)[0] ?? null;
  return {
    day: {
      min: Math.round(Math.min(...pick.map((hour) => hour.temp))),
      max: Math.round(Math.max(...pick.map((hour) => hour.temp))),
      wind: Math.round(Math.max(...pick.map((hour) => hour.wind))),
      precipitation: Math.round(pick.reduce((sum, hour) => sum + hour.precipitation, 0) * 10) / 10,
      symbol: common,
      text: symbolText(common),
    },
    hours: hours.filter((hour) => new Date(hour.time) >= new Date(now.getTime() - 3_600_000)).slice(0, 12).map(({ local: _, ...hour }) => ({ ...hour, text: symbolText(hour.symbol) })),
  };
}
