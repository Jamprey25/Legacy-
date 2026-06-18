// Vercel Function entry. The Hono app is exposed via the Vercel adapter; this single
// catch-all serves every /v1/* route. Runs on Node (Fluid Compute), not edge.
//
// Vercel's Node runtime treats a `default` export as a legacy `(req, res) => void`
// handler and ignores any returned `Response` — which silently hangs fetch-style
// handlers. We export named HTTP-method handlers instead so Vercel invokes the
// Web `fetch`-style signature that `hono/vercel`'s `handle` returns.

import { handle } from "hono/vercel";
import { createApp } from "../src/app.js";

export const config = { runtime: "nodejs" };

const app = createApp();
const handler = handle(app);

export const GET = handler;
export const POST = handler;
export const PUT = handler;
export const PATCH = handler;
export const DELETE = handler;
export const OPTIONS = handler;
export const HEAD = handler;
