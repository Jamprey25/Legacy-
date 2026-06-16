// Migration runner. Applies backend/migrations/*.sql in filename order against
// DATABASE_URL, tracking applied files in schema_migrations. Uses node-postgres (TCP)
// so multi-statement DDL files run as written; the app hot path uses the Neon HTTP
// driver separately. psql + Git remains the contract (DEC-28); this makes CI runnable.

import { readdir, readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import pg from "pg";

const url = process.env.DATABASE_URL;
if (!url) throw new Error("DATABASE_URL is not set.");

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, "..", "migrations");

const client = new pg.Client({ connectionString: url });
await client.connect();

try {
  await client.query(
    `CREATE TABLE IF NOT EXISTS schema_migrations (
       filename text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`,
  );

  const { rows } = await client.query<{ filename: string }>("SELECT filename FROM schema_migrations");
  const applied = new Set(rows.map((r) => r.filename));

  const files = (await readdir(migrationsDir)).filter((f) => /^\d+_.*\.sql$/.test(f)).sort();

  let count = 0;
  for (const file of files) {
    if (applied.has(file)) continue;
    const ddl = await readFile(join(migrationsDir, file), "utf8");
    console.log(`applying ${file}…`);
    // Each file is self-wrapped in BEGIN/COMMIT; run as a single multi-statement query.
    await client.query(ddl);
    await client.query("INSERT INTO schema_migrations (filename) VALUES ($1)", [file]);
    count++;
  }

  console.log(count === 0 ? "migrations up to date." : `applied ${count} migration(s).`);
} finally {
  await client.end();
}
