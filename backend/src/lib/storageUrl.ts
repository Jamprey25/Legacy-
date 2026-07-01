// Storage URL allowlist — blocks SSRF via attacker-controlled media_key (SEC-P2-2).

import { ApiError } from "./errors.js";

const DEFAULT_ALLOWED_HOSTS = [
  "public.blob.vercel-storage.com",
  "blob.vercel-storage.com",
];

function allowedHosts(): string[] {
  const extra =
    process.env.STORAGE_URL_ALLOWLIST?.split(",")
      .map((h) => h.trim().toLowerCase())
      .filter(Boolean) ?? [];
  return [...DEFAULT_ALLOWED_HOSTS, ...extra];
}

function hostAllowed(hostname: string): boolean {
  const host = hostname.toLowerCase();
  if (host === "stub.storage.example" && process.env.STORAGE_BACKEND === "stub") {
    return true;
  }
  return allowedHosts().some((allowed) => host === allowed || host.endsWith(`.${allowed}`));
}

/** Reject URLs that are not HTTPS or whose host is outside the storage allowlist. */
export function assertAllowedStorageUrl(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new ApiError("invalid_request", "Invalid media URL.");
  }
  if (parsed.protocol !== "https:") {
    throw new ApiError("invalid_request", "Media URL must use HTTPS.");
  }
  if (!hostAllowed(parsed.hostname)) {
    throw new ApiError("invalid_request", "Media URL host not allowed.");
  }
}

/** Ensure a blob key/URL references the expected memory (path contains memory UUID). */
export function assertMediaKeyBelongsToMemory(mediaKey: string, memoryId: string): void {
  if (!mediaKey.includes(memoryId)) {
    throw new ApiError("invalid_request", "media_key does not match memory_id.");
  }
}

/** Fetch only from allowlisted storage hosts. */
export async function fetchAllowedStorageUrl(url: string): Promise<Response> {
  assertAllowedStorageUrl(url);
  return fetch(url);
}
