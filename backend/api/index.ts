// Vercel Function entry. The Hono app is exposed via the Vercel adapter; this single
// catch-all serves every /v1/* route. Runs on Node (Fluid Compute), not edge.

import { handle } from "hono/vercel";
import { createApp } from "../src/app.js";

export const config = { runtime: "nodejs" };

const app = createApp();
export default handle(app);
