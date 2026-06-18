// APNs token-based push delivery (api-contract.md §7, task backend-apns-push).
//
// Uses token-based auth (JWT signed with ES256) over HTTP/2 to api.push.apple.com.
// Notification content is intentionally generic — never includes memory content or
// coordinates (task notes: "Something is waiting for you").
//
// Required env vars:
//   APNS_KEY_ID      — 10-char key ID from Apple Developer portal
//   APNS_TEAM_ID     — 10-char Team ID
//   APNS_PRIVATE_KEY — full .p8 key content (with -----BEGIN/END----- headers)
//   APNS_BUNDLE_ID   — app bundle ID, e.g. com.example.legacy
//   APNS_ENV         — "production" | "sandbox" (default: "sandbox")

import { SignJWT, importPKCS8 } from "jose";
import * as http2 from "node:http2";

const KEY_ID = process.env.APNS_KEY_ID ?? "";
const TEAM_ID = process.env.APNS_TEAM_ID ?? "";
const PRIVATE_KEY_PEM = process.env.APNS_PRIVATE_KEY ?? "";
const BUNDLE_ID = process.env.APNS_BUNDLE_ID ?? "";
const ENV = process.env.APNS_ENV ?? "sandbox";

const APNS_HOST =
  ENV === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";

// APNs JWT is valid for up to 1 hour. We cache it for 50 minutes.
let cachedToken: { jwt: string; generatedAt: number } | null = null;
const TOKEN_TTL_MS = 50 * 60 * 1000;

async function getApnsJwt(): Promise<string> {
  const now = Date.now();
  if (cachedToken && now - cachedToken.generatedAt < TOKEN_TTL_MS) {
    return cachedToken.jwt;
  }

  if (!KEY_ID || !TEAM_ID || !PRIVATE_KEY_PEM) {
    throw new Error("APNs env vars not configured (APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY).");
  }

  const key = await importPKCS8(PRIVATE_KEY_PEM, "ES256");
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: KEY_ID })
    .setIssuer(TEAM_ID)
    .setIssuedAt()
    .sign(key);

  cachedToken = { jwt, generatedAt: now };
  return jwt;
}

export type PushResult =
  | { ok: true }
  | { ok: false; reason: string; unregistered: boolean };

/**
 * Send a single APNs push to a device token. Best-effort — callers should not
 * block the user-facing response on this. Returns a result; never throws.
 */
export async function sendProximityPush(deviceToken: string): Promise<PushResult> {
  if (!deviceToken || !BUNDLE_ID) {
    return { ok: false, reason: "apns_not_configured", unregistered: false };
  }

  let jwt: string;
  try {
    jwt = await getApnsJwt();
  } catch (err) {
    console.warn("[apns] JWT generation failed:", (err as Error).message);
    return { ok: false, reason: "jwt_error", unregistered: false };
  }

  const payload = JSON.stringify({
    aps: {
      alert: {
        title: "Something is nearby",
        body: "Something is waiting for you.",
      },
      sound: "default",
      "content-available": 1,
    },
  });

  return new Promise((resolve) => {
    let settled = false;
    const done = (result: PushResult) => {
      if (!settled) {
        settled = true;
        resolve(result);
      }
    };

    const client = http2.connect(`https://${APNS_HOST}`, {
      rejectUnauthorized: ENV === "production",
    });

    client.on("error", (err) => {
      console.warn("[apns] connection error:", err.message);
      client.destroy();
      done({ ok: false, reason: "connection_error", unregistered: false });
    });

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      ":scheme": "https",
      ":authority": APNS_HOST,
      "authorization": `bearer ${jwt}`,
      "apns-topic": BUNDLE_ID,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
      "content-length": Buffer.byteLength(payload).toString(),
    });

    req.setEncoding("utf8");
    req.write(payload);
    req.end();

    let statusCode = 0;
    req.on("response", (headers) => {
      statusCode = Number(headers[":status"] ?? 0);
    });

    let body = "";
    req.on("data", (chunk) => { body += chunk; });

    req.on("end", () => {
      client.close();
      if (statusCode === 200) {
        done({ ok: true });
        return;
      }
      let reason = "unknown";
      let unregistered = false;
      try {
        const parsed = JSON.parse(body) as { reason?: string };
        reason = parsed.reason ?? reason;
        unregistered = reason === "Unregistered" || reason === "BadDeviceToken";
      } catch {
        // non-JSON body
      }
      console.warn(`[apns] delivery failed (${statusCode}): ${reason}`);
      done({ ok: false, reason, unregistered });
    });

    // Timeout after 5s — don't block the scan response.
    setTimeout(() => {
      if (!settled) {
        client.destroy();
        done({ ok: false, reason: "timeout", unregistered: false });
      }
    }, 5000);
  });
}
