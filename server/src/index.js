import pg from "pg";
import { createApp } from "./app.js";

const port = Number(process.env.PORT ?? 8080);
const version = process.env.APP_VERSION ?? "dev";

// Без DATABASE_URL сервер стартует, но /health покажет db: false.
const db = process.env.DATABASE_URL
  ? new pg.Pool({ connectionString: process.env.DATABASE_URL, max: 5, connectionTimeoutMillis: 3000 })
  : null;

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
