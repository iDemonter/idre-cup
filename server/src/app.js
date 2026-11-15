import express from "express";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { ApiError, mountApi } from "./api.js";

const rulesPath = fileURLToPath(new URL("../config/rules.json", import.meta.url));

/**
 * Собирает приложение. База передаётся снаружи, чтобы тесты могли подставить свою.
 * Без базы работают только /health и /v1/config.
 * @param {{ db?: import("pg").Pool | null, version?: string, attemptLimit?: number }} options
 * attemptLimit: сколько раз за 10 минут с одного адреса можно создать кубок или войти по коду.
 */
export function createApp({ db = null, version = "dev", attemptLimit = 30 } = {}) {
  // Правила и очки. Меняются правкой config/rules.json и перезапуском сервера, без новой сборки приложения.
  const rules = JSON.parse(readFileSync(rulesPath, "utf8"));

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

  app.get("/v1/config", (_req, res) => {
    res.json(rules);
  });

  if (db && typeof db.connect === "function") {
    mountApi(app, { db, rules, attemptLimit });
  }

  app.use((_req, res) => {
    res.status(404).json({ error: "not_found" });
  });

  // eslint-disable-next-line no-unused-vars
  app.use((error, _req, res, _next) => {
    if (error instanceof ApiError) {
      res.status(error.status).json({ error: error.code, message: error.message });
      return;
    }
    if (error?.type === "entity.parse.failed" || error?.type === "entity.too.large") {
      res.status(error.status ?? 400).json({ error: "bad_request", message: "Тело запроса не разобрать" });
      return;
    }
    console.error(error);
    res.status(500).json({ error: "internal_error" });
  });

  return app;
}
