import { describe, expect, it } from "vitest";
import { clockSkew } from "../src/middleware/clockSkew.js";
import { ApiError } from "../src/lib/errors.js";

async function runClockSkew(
  path: string,
  headers: Record<string, string> = {},
): Promise<{ ok: boolean; code?: string }> {
  let nextCalled = false;
  const ctx = {
    req: {
      url: `https://example.com${path}`,
      header: (name: string) => headers[name.toLowerCase()] ?? headers[name],
    },
  } as Parameters<typeof clockSkew>[0];

  try {
    await clockSkew(ctx, async () => {
      nextCalled = true;
    });
    return { ok: nextCalled };
  } catch (err) {
    if (err instanceof ApiError) return { ok: false, code: err.code };
    throw err;
  }
}

describe("clockSkew", () => {
  it("requires timestamp on mutating routes", async () => {
    const result = await runClockSkew("/v1/memories");
    expect(result.ok).toBe(false);
    expect(result.code).toBe("clock_skew");
  });

  it("allows health without timestamp", async () => {
    const result = await runClockSkew("/v1/health");
    expect(result.ok).toBe(true);
  });

  it("allows internal webhook without timestamp", async () => {
    const result = await runClockSkew("/v1/internal/webhook/storage");
    expect(result.ok).toBe(true);
  });

  it("accepts a fresh timestamp", async () => {
    const result = await runClockSkew("/v1/discovery/scan", {
      "X-Request-Timestamp": new Date().toISOString(),
    });
    expect(result.ok).toBe(true);
  });
});
