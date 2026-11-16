// Страница викторины для телевизора: /tv/<код кубка>. Опрашивает /tv/<код>/state раз в секунду.
// Одна страница без внешних файлов: откроется в браузере любого Smart TV или на телефоне через AirPlay.
export const TV_PAGE = `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Idre Cup · Викторина</title>
<style>
  :root { --base:#0b1026; --surface:#161d3d; --raised:#222b55; --text:#f4f6ff; --muted:#9aa3c9; --accent:#4fd8ff;
          --a:#ff4d6d; --b:#4f8bff; --c:#ffc94d; --d:#33d17a; }
  * { box-sizing: border-box; }
  html, body { margin:0; height:100%; background:var(--base); color:var(--text);
    font-family: -apple-system, "SF Pro Rounded", "Segoe UI", Roboto, sans-serif; }
  body { display:flex; flex-direction:column; padding:3.5vh 4vw; gap:3vh; }
  header { display:flex; justify-content:space-between; align-items:baseline; }
  .overline { color:var(--muted); font-weight:700; letter-spacing:.12em; font-size:2.2vh; text-transform:uppercase; }
  h1 { margin:0; font-size:6.5vh; line-height:1.1; }
  .timer { font-size:7vh; font-weight:800; color:var(--accent); font-variant-numeric:tabular-nums; }
  main { flex:1; display:flex; gap:3vw; min-height:0; }
  .stage { flex:3; display:flex; flex-direction:column; gap:3vh; justify-content:flex-start; overflow:hidden; min-width:0; }
  .stage h1 { font-size:5.2vh; }
  .board { flex:1.2; background:var(--surface); border-radius:3vh; padding:3vh 2vw; overflow:hidden; }
  .board h2 { margin:0 0 2vh; font-size:2.4vh; color:var(--muted); letter-spacing:.12em; }
  .row { display:flex; justify-content:space-between; font-size:3.4vh; padding:1vh 0; border-bottom:1px solid var(--raised); }
  .row b { color:var(--accent); font-variant-numeric:tabular-nums; }
  .options { display:grid; grid-template-columns:1fr 1fr; gap:2vh; }
  .option { border-radius:2.5vh; padding:3vh 2vw; font-size:4.2vh; font-weight:700; display:flex; gap:1.5vw; align-items:center; min-height:14vh; transition:opacity .3s; }
  .option .letter { font-size:3vh; opacity:.85; }
  .option .count { margin-left:auto; font-size:3vh; opacity:.9; }
  .o0 { background:var(--a); } .o1 { background:var(--b); } .o2 { background:var(--c); color:#1a1300; } .o3 { background:var(--d); color:#04210f; }
  .dim { opacity:.25; }
  .big { font-size:9vh; font-weight:800; }
  .hint { color:var(--muted); font-size:3vh; }
  .podium .row { font-size:5vh; }
</style>
</head>
<body>
<header>
  <div><div class="overline" id="cup">Idre Cup</div><h1 id="title">Викторина</h1></div>
  <div class="timer" id="timer"></div>
</header>
<main>
  <section class="stage" id="stage"><div class="hint">Подключаемся…</div></section>
  <aside class="board"><h2>СЧЁТ</h2><div id="scores"></div></aside>
</main>
<script>
const letters = ["A", "B", "C", "D"];
const esc = (text) => String(text).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
async function tick() {
  try {
    const reply = await fetch(location.pathname.replace(/\\/$/, "") + "/state", { cache: "no-store" });
    if (!reply.ok) throw new Error(reply.status);
    render(await reply.json());
  } catch (error) {
    document.getElementById("stage").innerHTML = '<div class="hint">Нет связи с сервером. Пробуем снова…</div>';
  }
}
function render(data) {
  document.getElementById("cup").textContent = data.cup;
  const quiz = data.quiz;
  const stage = document.getElementById("stage");
  const timer = document.getElementById("timer");
  const title = document.getElementById("title");
  const scores = (quiz && quiz.scores) || [];
  document.getElementById("scores").innerHTML = scores.length
    ? scores.map((row, index) => '<div class="row"><span>' + (index + 1) + ". " + esc(row.name) + "</span><b>" + row.score + "</b></div>").join("")
    : data.people.map((name) => '<div class="row"><span>' + esc(name) + "</span><b>0</b></div>").join("");
  if (!quiz || (quiz.status === "finished" && quiz.phase !== "finished")) {
    title.textContent = "Викторина";
    timer.textContent = "";
    stage.innerHTML = '<div class="big">Ждём начала</div><div class="hint">Админ начинает викторину в приложении: «Вечер» → «Викторина». Отвечать — на своём телефоне.</div>';
    return;
  }
  if (quiz.phase === "intro") {
    title.textContent = "Викторина";
    timer.textContent = quiz.left;
    stage.innerHTML = '<div class="big">Приготовьтесь!</div><div class="hint">' + quiz.count + " вопросов, на каждый " + "20 секунд. Отвечайте на своих телефонах во вкладке «Вечер». Чем быстрее правильный ответ, тем больше очков.</div>";
    return;
  }
  if (quiz.phase === "finished") {
    title.textContent = "Итоги викторины";
    timer.textContent = "";
    const results = quiz.results || scores;
    stage.innerHTML = '<div class="podium">' + results.map((row, index) =>
      '<div class="row"><span>' + (row.place || index + 1) + ". " + esc(row.name) + "</span><b>" + (row.points !== undefined ? "+" + row.points + " в зачёт" : row.score) + "</b></div>").join("") + "</div>";
    return;
  }
  title.textContent = "Вопрос " + (quiz.index + 1) + " из " + quiz.count;
  timer.textContent = quiz.phase === "question" ? quiz.left : "";
  const reveal = quiz.phase === "reveal";
  stage.innerHTML = '<h1>' + esc(quiz.question.text) + '</h1><div class="options">' +
    quiz.question.options.map((option, index) =>
      '<div class="option o' + index + (reveal && index !== quiz.correct ? " dim" : "") + '"><span class="letter">' + letters[index] + "</span>" + esc(option) +
      (reveal ? '<span class="count">' + quiz.counts[index] + "</span>" : "") + "</div>").join("") +
    "</div>" + '<div class="hint">' + (reveal ? "Правильный ответ: " + letters[quiz.correct] : "Ответили: " + (quiz.answered || 0) + " из " + data.people.length) + "</div>";
}
tick();
setInterval(tick, 1000);
</script>
</body>
</html>`;
