// Hono app assembly. Shared across the Vercel handler (api/index.ts) and the local
// dev server (dev-server.ts), so both run identical middleware + routing.

import { Hono } from "hono";
import { errorHandler } from "./lib/errors.js";
import { requestId, clockSkew, type AuthVars } from "./middleware/auth.js";
import { authRoutes } from "./routes/auth.js";
import { memoriesRoutes } from "./routes/memories.js";
import { discoveryRoutes } from "./routes/discovery.js";
import { webhookRoutes } from "./routes/webhook.js";

export function createApp() {
  const app = new Hono<{ Variables: AuthVars }>().basePath("/v1");

  app.use("*", requestId);
  app.use("*", clockSkew);
  app.onError(errorHandler);

  app.get("/health", (c) => c.json({ ok: true }));
  app.route("/auth", authRoutes);
  app.route("/memories", memoriesRoutes);
  app.route("/discovery", discoveryRoutes);
  app.route("/internal/webhook", webhookRoutes);

  return app;
}

export type App = ReturnType<typeof createApp>;
