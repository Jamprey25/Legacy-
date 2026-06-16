// Token verification (Apple/Google identity tokens) + session token issue/verify.
// External tokens: verified against the provider's published JWKS (RS256). Session
// tokens: HS256 signed with SESSION_JWT_SECRET, validated statelessly (no DB lookup).

import { SignJWT, jwtVerify, createRemoteJWKSet, type JWTPayload } from "jose";
import { ApiError } from "./errors.js";

const APPLE_JWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));
const GOOGLE_JWKS = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"));

export interface ExternalIdentity {
  sub: string;            // provider's stable user id
  email: string | null;   // may be absent/relay
}

/** Verify an Apple identity token. Throws ApiError(unauthorized) on any failure. */
export async function verifyAppleToken(idToken: string): Promise<ExternalIdentity> {
  const aud = requireEnv("APPLE_BUNDLE_ID");
  return verifyExternal(idToken, APPLE_JWKS, "https://appleid.apple.com", aud);
}

/** Verify a Google ID token. Throws ApiError(unauthorized) on any failure. */
export async function verifyGoogleToken(idToken: string): Promise<ExternalIdentity> {
  const aud = requireEnv("GOOGLE_CLIENT_ID");
  // Google issues iss as either of these.
  return verifyExternal(idToken, GOOGLE_JWKS, ["https://accounts.google.com", "accounts.google.com"], aud);
}

async function verifyExternal(
  idToken: string,
  jwks: ReturnType<typeof createRemoteJWKSet>,
  issuer: string | string[],
  audience: string,
): Promise<ExternalIdentity> {
  try {
    const { payload } = await jwtVerify(idToken, jwks, { issuer, audience });
    if (!payload.sub) throw new Error("missing sub");
    const email = typeof payload.email === "string" ? payload.email : null;
    return { sub: payload.sub, email };
  } catch {
    throw new ApiError("unauthorized", "Could not verify your sign-in.");
  }
}

export interface SessionClaims extends JWTPayload {
  sub: string;            // user id
  age_tier: "adult" | "minor";
}

/** Issue a session JWT. Expiry from SESSION_TTL_DAYS. */
export async function signSession(userId: string, ageTier: "adult" | "minor"): Promise<{ token: string; expiresAt: Date }> {
  const ttlDays = Number(process.env.SESSION_TTL_DAYS ?? "30");
  const expiresAt = new Date(Date.now() + ttlDays * 86_400_000);
  const token = await new SignJWT({ age_tier: ageTier })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime(expiresAt)
    .sign(secret());
  return { token, expiresAt };
}

/** Verify a session JWT. Throws ApiError(token_expired|unauthorized). */
export async function verifySession(token: string): Promise<SessionClaims> {
  try {
    const { payload } = await jwtVerify(token, secret());
    if (!payload.sub) throw new Error("missing sub");
    return payload as SessionClaims;
  } catch (err) {
    if (err instanceof Error && err.name === "JWTExpired") {
      throw new ApiError("token_expired", "Your session has expired. Please sign in again.");
    }
    throw new ApiError("unauthorized", "Invalid session.");
  }
}

function secret(): Uint8Array {
  return new TextEncoder().encode(requireEnv("SESSION_JWT_SECRET"));
}

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`${key} is not set`);
  return v;
}
