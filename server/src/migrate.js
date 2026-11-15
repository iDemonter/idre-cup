import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const folder = fileURLToPath(new URL("../db/migrations/", import.meta.url));

/**
 * Применяет файлы db/migrations/*.sql по порядку имён, каждый один раз.
 * Что уже применено, записано в таблице schema_migrations.
 * @param {import("pg").Pool} db
 */
export async function migrate(db, log = console.log) {
  await db.query(
    "create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())",
  );
  const done = new Set((await db.query("select name from schema_migrations")).rows.map((row) => row.name));
  const files = (await readdir(folder)).filter((file) => file.endsWith(".sql")).sort();

  for (const file of files) {
    if (done.has(file)) continue;
    const sql = await readFile(folder + file, "utf8");
    const client = await db.connect();
    try {
      await client.query("begin");
      await client.query(sql);
      await client.query("insert into schema_migrations (name) values ($1)", [file]);
      await client.query("commit");
      log(`Миграция применена: ${file}`);
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }
}
