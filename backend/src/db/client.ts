// Neon serverless driver. The HTTP `sql` tagged template is ideal for the stateless,
// one-shot queries this API makes (validate → respond → forget). No connection pool to
// manage across Vercel Function invocations.

import { neon } from "@neondatabase/serverless";

const url = process.env.DATABASE_URL;
if (!url) {
  throw new Error("DATABASE_URL is not set. Copy backend/.env.example to .env.local.");
}

/**
 * Tagged-template SQL. Parameterized by construction — interpolated values are sent as
 * bind params, never string-concatenated, so this is injection-safe:
 *   await sql`SELECT * FROM users WHERE id = ${id}`
 */
export const sql = neon(url);

export type Row = Record<string, unknown>;
