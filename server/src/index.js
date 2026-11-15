import pg from "pg";
import { createApp } from "./app.js";
import { migrate } from "./migrate.js";

const port = Number(process.env.PORT ?? 8080);
const version = process.env.APP_VERSION ?? "dev";

// Без DATABASE_URL сервер стартует, но /health покажет db: false.
const db = process.env.DATABASE_URL
  ? new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 5, connectionTimeoutMillis: 3000 })
  : null;

// База в соседнем контейнере может подняться позже сервера: ждём её до минуты.
if (db) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      await migrate(db);
      break;
    } catch (error) {
      if (attempt >= 30) throw error;
      console.log(`База ещё не готова (${error.message}), попытка ${attempt}`);
      await new Promise((resolve) => setTimeout(resolve, 2000));
    }
  }
}

const app = createApp({ db, version });

const server = app.listen(port, () => {
  console.log(`Idre Cup server ${version} слушает порт ${port}`);
});

async function shutdown() {
  server.close();
  if (db) await db.end();
  process.exit(0);
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
