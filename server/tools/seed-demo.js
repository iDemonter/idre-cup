// Демо-кубок для проверки приложения: пять участников и треки за три дня у вершины Idre Fjäll.
// Запуск при работающем сервере:  node tools/seed-demo.js http://127.0.0.1:8080
// Печатает код кубка и токены участников (JSON).

const server = (process.argv[2] ?? "http://127.0.0.1:8080").replace(/\/$/, "");

async function call(method, path, { token, body } = {}) {
  const res = await fetch(server + path, {
    method,
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`${method} ${path}: ${res.status} ${JSON.stringify(json)}`);
  return json;
}

// Круг: подъём на 200 м и спуск с заданной скоростью, точка в секунду.
function lap(start, speed, east) {
  const points = [];
  const lat0 = 61.8881;
  const lon0 = 12.8587 + east / 52_456;
  let t = start;
  let north = 0;
  for (let second = 0; second < 280; second += 1) {
    north += 5;
    points.push([t, lat0 + north / 111_320, lon0, 680 + (second / 280) * 200, 5, 5]);
    t += 1;
  }
  let alt = 880;
  while (alt > 680) {
    north -= speed;
    alt -= speed * 0.15;
    points.push([t, lat0 + north / 111_320, lon0, alt, speed, 5]);
    t += 1;
  }
  return points;
}

const now = Math.floor(Date.now() / 1000);
const startsOn = new Date((now - 2 * 86_400) * 1000).toISOString().slice(0, 10);

// Имя и скорости спусков (м/с) по дням: позавчера, вчера, сегодня.
const people = [
  ["Иван", [[19, 17], [21.2, 18, 16], [20.4, 18.5]]],
  ["Олег", [[20.5, 15], [19, 17], [18.2]]],
  ["Анна", [[16, 15, 14], [17.5, 16, 15, 14], [16.8, 15, 14]]],
  ["Макс", [[22.3], [], [21.7, 12]]],
  ["Юля", [[14, 13], [15.5, 14], []]],
];

const created = await call("POST", "/v1/cups", { body: { cupName: "Idre Cup 2027", name: people[0][0], startsOn, prize: "Ужин за счёт остальных" } });
const tokens = { [people[0][0]]: created.token };
for (const [name] of people.slice(1)) {
  tokens[name] = (await call("POST", "/v1/join", { body: { code: created.cup.code, name } })).token;
}
await call("PATCH", "/v1/cup", { token: created.token, body: { home: { lat: 61.88634, lon: 12.83393 } } });

for (const [index, [name, days]] of people.entries()) {
  for (const [dayIndex, speeds] of days.entries()) {
    const daysAgo = 2 - dayIndex;
    // Сегодняшние круги заканчиваются несколько минут назад, чтобы попасть в «живые» позиции.
    let start = now - daysAgo * 86_400 - speeds.length * 420 - 120;
    const points = [];
    for (const speed of speeds) {
      const one = lap(start, speed, index * 150 - 300);
      points.push(...one);
      start = one.at(-1)[0] + 60;
    }
    if (points.length > 0) await call("POST", "/v1/tracks", { token: tokens[name], body: { points } });
  }
}

console.log(JSON.stringify({ server, code: created.cup.code, tokens }, null, 2));
