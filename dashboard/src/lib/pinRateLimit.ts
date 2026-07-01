/** In-memory PIN brute-force guard for dashboard write routes (SEC-P4-2). */

const WINDOW_MS = 15 * 60 * 1000;
const MAX_FAILURES = 10;
const LOCKOUT_MS = 30 * 60 * 1000;

interface PinBucket {
  failures: number;
  windowStart: number;
  lockedUntil: number | null;
}

const buckets = new Map<string, PinBucket>();

export function pinClientIp(request: Request): string {
  const fwd = request.headers.get("x-forwarded-for");
  if (fwd) return fwd.split(",")[0]!.trim();
  return request.headers.get("x-real-ip") ?? "unknown";
}

export function pinLockoutStatus(ip: string): { locked: boolean; retryAfterS?: number } {
  const bucket = buckets.get(ip);
  if (bucket?.lockedUntil && Date.now() < bucket.lockedUntil) {
    return {
      locked: true,
      retryAfterS: Math.max(1, Math.ceil((bucket.lockedUntil - Date.now()) / 1000)),
    };
  }
  return { locked: false };
}

export function recordPinFailure(ip: string): void {
  const now = Date.now();
  let bucket = buckets.get(ip);
  if (!bucket || now - bucket.windowStart > WINDOW_MS) {
    bucket = { failures: 0, windowStart: now, lockedUntil: null };
  }
  bucket.failures += 1;
  if (bucket.failures >= MAX_FAILURES) {
    bucket.lockedUntil = now + LOCKOUT_MS;
    bucket.failures = 0;
  }
  buckets.set(ip, bucket);
}

export function recordPinSuccess(ip: string): void {
  buckets.delete(ip);
}
