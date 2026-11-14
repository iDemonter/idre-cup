import express from "express";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const rulesPath = fileURLToPath(new URL("../config/rules.json", import.meta.url));

/**
 * Собирает приложение. База передаётся снаружи, чтобы тесты работали без Postgres.
 * @param {{ db?: { query: (sql: string) => Promise<unknown> } | null, version?: string }} options
 */
export function createApp({ db = null, version = "dev" } = {}) {
  const app = express();
  app.disable("x-powered-by");
  app.use(express.json({ limit: "2mb" }));

  // Проверка здоровья: сервер жив, база отвечает.
  app.get("/health", async (_req, res) => {
    let dbOk = false;
    if (db) {
      try {
        await db.query("select 1");
        dbOk = true;
      } catch {
        dbOk = false;
      }
    }
    res.json({ ok: true, version, db: dbOk, time: new Date().toISOString() });
  });

  // Правила и очки. Меняются правкой config/rules.json, без новой сборки приложения.
  app.get("/v1/config", async (_req, res, next) => {
    try {
      const rules = JSON.parse(await readFile(rulesPath, "utf8"));
      res.json(rules);
    } catch (error) {
      next(error);
    }
  });

  app.use((_req, res) => {
    res.status(404).json({ error: "not_found" });
  });

  // eslint-disable-next-line no-unused-vars
  app.use((error, _req, res, _next) => {
    console.error(error);
    res.status(500).json({ error: "internal_error" });
  });

  return app;
}
