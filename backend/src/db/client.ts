// Driver-agnostic SQL client.
//
// Production (Vercel + Neon): the Neon serverless HTTP driver — ideal for the
// stateless, one-shot queries this API makes (validate → respond → forget), no
// connection pool to manage across Function invocations.
//
// Non-Neon URLs (CI postgres service container, local scratch DBs): node-postgres,
// lazily imported so it stays a devDependency and never ships in the prod bundle.
// The neon() driver throws at construction on non-Neon URLs, which made the
// integration test suite unrunnable anywhere until this fallback (2026-07-07).

import { neon } from "@neondatabase/serverless";

const url = process.env.DATABASE_URL;
if (!url) {
  throw new Error("DATABASE_URL is not set. Copy backend/.env.example to .env.local.");
}

export type Row = Record<string, unknown>;

/**
 * Both call forms used in this codebase:
 *   await sql`SELECT * FROM users WHERE id = ${id}`   // tagged template
 *   await sql(queryText, params)                      // dynamic query building
 * Interpolated values are always sent as bind params, never string-concatenated,
 * so both forms are injection-safe by construction.
 */
type SqlFn = (first: TemplateStringsArray | string, ...rest: unknown[]) => Promise<Row[]>;

function isNeonUrl(raw: string): boolean {
  try {
    return new URL(raw).hostname.endsWith(".neon.tech");
  } catch {
    return false;
  }
}

function createPgSql(connectionString: string): SqlFn {
  let poolPromise: Promise<import("pg").Pool> | null = null;
  const getPool = () => {
    poolPromise ??= import("pg").then(({ default: pg }) => new pg.Pool({ connectionString }));
    return poolPromise;
  };
  return async (first, ...rest) => {
    const pool = await getPool();
    if (typeof first === "string") {
      // Function form: sql(text, params?)
      const params = (rest[0] as unknown[] | undefined) ?? [];
      return (await pool.query(first, params)).rows as Row[];
    }
    // Tagged-template form: interpolations become $1..$n bind params.
    let text = first[0] ?? "";
    for (let i = 0; i < rest.length; i++) {
      text += `$${i + 1}${first[i + 1] ?? ""}`;
    }
    return (await pool.query(text, rest)).rows as Row[];
  };
}

export const sql: SqlFn = isNeonUrl(url)
  ? (neon(url) as unknown as SqlFn)
  : createPgSql(url);
