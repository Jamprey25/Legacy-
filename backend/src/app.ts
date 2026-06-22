// Hono app assembly. Shared across the Vercel handler (api/index.ts) and the local
// dev server (dev-server.ts), so both run identical middleware + routing.

import { Hono } from "hono";
import { errorHandler } from "./lib/errors.js";
import { requestId, clockSkew, type AuthVars } from "./middleware/auth.js";
import { authRoutes } from "./routes/auth.js";
import { memoriesRoutes } from "./routes/memories.js";
import { discoveryRoutes } from "./routes/discovery.js";
import { webhookRoutes } from "./routes/webhook.js";
import { devicesRoutes } from "./routes/devices.js";
import { uploadsRoutes } from "./routes/uploads.js";
import { userRoutes } from "./routes/user.js";
import { attestRoutes } from "./routes/attest.js";

export function createApp() {
  const app = new Hono<{ Variables: AuthVars }>().basePath("/v1");

  app.use("*", requestId);
  app.use("*", clockSkew);
  app.onError(errorHandler);

  app.get("/health", (c) => c.json({ ok: true }));

  // TEMPORARY maintenance route — purge all blobs. Guarded by WEBHOOK_SECRET. Remove after use.
  app.post("/internal/purge-blobs", async (c) => {
    if (c.req.header("x-maintenance-secret") !== process.env.WEBHOOK_SECRET) {
      return c.json({ error: "forbidden" }, 403);
    }
    const { list, del } = await import("@vercel/blob");
    let cursor: string | undefined;
    let total = 0;
    do {
      const res = await list({ cursor, limit: 1000 });
      if (res.blobs.length) {
        await del(res.blobs.map((b) => b.url));
        total += res.blobs.length;
      }
      cursor = res.cursor;
    } while (cursor);
    return c.json({ purged: total });
  });
  app.route("/auth", authRoutes);
  app.route("/auth/attest", attestRoutes);
  app.route("/memories", memoriesRoutes);
  app.route("/discovery", discoveryRoutes);
  app.route("/devices", devicesRoutes);
  app.route("/uploads", uploadsRoutes);
  app.route("/user", userRoutes);
  app.route("/internal/webhook", webhookRoutes);

  return app;
}

export type App = ReturnType<typeof createApp>;
