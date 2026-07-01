// Unit tests for SEC-P1-1: JWT session revocation.

import { describe, it, expect, vi, beforeEach } from "vitest";
import { signSession, verifySession } from "../src/lib/jwt.js";
import { requireAuth } from "../src/middleware/auth.js";

process.env.SESSION_JWT_SECRET = "test-secret-for-revocation-tests-32chars!!";

vi.mock("../src/db/sessions.js", () => ({
  isSessionRevoked: vi.fn<() => Promise<boolean>>(),
}));

import * as sessionsDb from "../src/db/sessions.js";
const mockIsRevoked = vi.mocked(sessionsDb.isSessionRevoked);

interface MockReqOpts { method?: string; }

async function runMiddleware(token: string, opts: MockReqOpts = {}): Promise<{ status: number; body: unknown }> {
  const { method = "GET" } = opts;
  let nextCalled = false;
  let userId: string | undefined;
  let deviceId: string | undefined;

  const ctx = {
    req: {
      method,
      header: (name: string) => {
        if (name === "Authorization") return `Bearer ${token}`;
        return undefined;
      },
    },
    set: (k: string, v: unknown) => {
      if (k === "userId") userId = v as string;
      if (k === "deviceId") deviceId = v as string | undefined;
    },
  } as Parameters<typeof requireAuth>[0];

  try {
    await requireAuth(ctx, async () => { nextCalled = true; });
    return { status: 200, body: { userId, deviceId, next: nextCalled } };
  } catch (err: unknown) {
    const e = err as { code?: string; status?: number };
    return { status: e.status ?? 401, body: { error: e.code } };
  }
}

describe("signSession / did claim", () => {
  it("embeds did when deviceId provided", async () => {
    const { token } = await signSession("user-1", "adult", "device-abc");
    const claims = await verifySession(token);
    expect(claims.did).toBe("device-abc");
  });

  it("omits did when deviceId absent", async () => {
    const { token } = await signSession("user-1", "adult");
    const claims = await verifySession(token);
    expect(claims.did).toBeUndefined();
  });
});

describe("requireAuth revocation check", () => {
  beforeEach(() => mockIsRevoked.mockReset());

  it("passes when session is active", async () => {
    mockIsRevoked.mockResolvedValueOnce(false);
    const { token } = await signSession("u1", "adult", "d1");
    const result = await runMiddleware(token, { method: "GET" });
    expect(result.status).toBe(200);
    expect((result.body as { userId: string }).userId).toBe("u1");
    expect(mockIsRevoked).toHaveBeenCalledWith("u1", "d1");
  });

  it("returns token_expired when session is revoked", async () => {
    mockIsRevoked.mockResolvedValueOnce(true);
    const { token } = await signSession("u2", "adult", "d2");
    const result = await runMiddleware(token);
    expect(result.status).toBe(401);
    expect((result.body as { error: string }).error).toBe("token_expired");
  });

  it("skips revocation check for old tokens without did", async () => {
    const { token } = await signSession("u3", "adult");
    const result = await runMiddleware(token, { method: "GET" });
    expect(result.status).toBe(200);
    expect(mockIsRevoked).not.toHaveBeenCalled();
  });
});
