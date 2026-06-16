// Local dev server — runs the same Hono app over Node HTTP. `npm run dev`.
// Loads .env.local first.

import { serve } from "@hono/node-server";
import { createApp } from "./app.js";

const port = Number(process.env.PORT ?? "8787");
serve({ fetch: createApp().fetch, port }, (info) => {
  console.log(`Legacy API on http://localhost:${info.port}/v1`);
});
