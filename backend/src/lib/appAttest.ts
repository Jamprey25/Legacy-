// Apple App Attest server-side verification (M5).
//
// Flow:
//   1. Device calls GET /v1/auth/attest/challenge → {challenge_token, expires_at}
//   2. iOS attests its key: DCAppAttestService.attestKey(keyId, SHA256(challenge))
//   3. Device calls POST /v1/auth/attest/register with the attestation object
//   4. On each sensitive request (drop, unlock) iOS sends an assertion generated with
//      DCAppAttestService.generateAssertion(keyId, SHA256(challenge)) where challenge
//      is a fresh token from step 1.
//
// Feature flag: APP_ATTEST_REQUIRED (default false). When false, assertions are
// accepted/ignored and the bypass is audit-logged. Flip to true at M5 TestFlight cut.
//
// Env vars (all required when APP_ATTEST_REQUIRED=true):
//   APP_ATTEST_TEAM_ID    — Apple Developer Team ID (e.g. "ABC123DEF4")
//   APP_ATTEST_BUNDLE_ID  — App bundle ID (e.g. "com.yourcompany.legacy")
//   APP_ATTEST_SECRET     — 32+ byte secret for HMAC-signing challenges
//   APP_ATTEST_ROOT_CA    — PEM of Apple App Attest Root CA G2 (see apple.com/certificateauthority)

import { createHash, createHmac, createVerify, X509Certificate, KeyObject, createPublicKey } from "crypto";

// ---------------------------------------------------------------------------
// Feature flag
// ---------------------------------------------------------------------------

export function isAttestRequired(): boolean {
  return process.env.APP_ATTEST_REQUIRED === "true";
}

// ---------------------------------------------------------------------------
// Minimal CBOR decoder (supports types needed for App Attest only)
// ---------------------------------------------------------------------------

type CborPrimitive = Buffer | string | number;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type CborValue = CborPrimitive | CborValue[] | Record<string, any>;

function decodeCborAt(buf: Buffer, offset: number): [CborValue, number] {
  const b = buf[offset]!;
  const major = b >> 5;
  const info = b & 0x1f;

  let len: number;
  let pos = offset + 1;

  if (info < 24) {
    len = info;
  } else if (info === 24) {
    len = buf[pos++]!;
  } else if (info === 25) {
    len = buf.readUInt16BE(pos); pos += 2;
  } else if (info === 26) {
    len = buf.readUInt32BE(pos); pos += 4;
  } else {
    throw new Error(`CBOR: unsupported additional info ${info} at offset ${offset}`);
  }

  switch (major) {
    case 0: return [len, pos];
    case 2: {
      const bytes = buf.slice(pos, pos + len);
      return [bytes, pos + len];
    }
    case 3: {
      const text = buf.slice(pos, pos + len).toString("utf8");
      return [text, pos + len];
    }
    case 4: {
      const arr: CborValue[] = [];
      for (let i = 0; i < len; i++) {
        const [item, next] = decodeCborAt(buf, pos);
        arr.push(item); pos = next;
      }
      return [arr, pos];
    }
    case 5: {
      const map: Record<string, CborValue> = {};
      for (let i = 0; i < len; i++) {
        const [key, p1] = decodeCborAt(buf, pos);
        const [val, p2] = decodeCborAt(buf, p1);
        map[String(key)] = val; pos = p2;
      }
      return [map, pos];
    }
    default:
      throw new Error(`CBOR: unsupported major type ${major} at offset ${offset}`);
  }
}

function decodeCbor(buf: Buffer): CborValue {
  const [val] = decodeCborAt(buf, 0);
  return val;
}

// ---------------------------------------------------------------------------
// authenticatorData binary parser
// ---------------------------------------------------------------------------

interface AuthDataBase {
  rpIdHash: Buffer;   // 32 bytes
  flags: number;
  signCount: number;  // uint32 big-endian
}

interface AuthDataWithCred extends AuthDataBase {
  aaguid: Buffer;            // 16 bytes
  credentialId: Buffer;
  credentialPublicKeyRaw: Buffer; // CBOR COSE key
}

function parseAuthDataBase(buf: Buffer): AuthDataBase {
  if (buf.length < 37) throw new Error("authData too short");
  return {
    rpIdHash: buf.slice(0, 32),
    flags: buf[32]!,
    signCount: buf.readUInt32BE(33),
  };
}

function parseAuthDataFull(buf: Buffer): AuthDataWithCred {
  if (buf.length < 55) throw new Error("authData too short for attested credential data");
  const base = parseAuthDataBase(buf);
  const aaguid = buf.slice(37, 53);
  const credLen = buf.readUInt16BE(53);
  const credentialId = buf.slice(55, 55 + credLen);
  const credentialPublicKeyRaw = buf.slice(55 + credLen);
  return { ...base, aaguid, credentialId, credentialPublicKeyRaw };
}

// ---------------------------------------------------------------------------
// COSE EC P-256 key → SubjectPublicKeyInfo DER
// ---------------------------------------------------------------------------
// COSE key map for P-256:
//   1  (kty)  → 2 (EC2)
//  -1  (crv)  → 1 (P-256)
//  -2  (x)    → 32-byte x coordinate
//  -3  (y)    → 32-byte y coordinate
//
// CBOR integer keys are encoded as: positive n → n; negative -n → (~n = n-1)
// So key -1 = 0x20, -2 = 0x21, -3 = 0x22 in CBOR major type 1.

function coseP256ToDer(coseRaw: Buffer): Buffer {
  const key = decodeCbor(coseRaw) as Record<string, CborValue>;
  // CBOR map keys may be numbers encoded as strings by our decoder.
  // Negative integers come through as negative numbers in key stringification.
  // Try both numeric and string forms.
  const x = (key["-2"] ?? key[String(-2)]) as Buffer | undefined;
  const y = (key["-3"] ?? key[String(-3)]) as Buffer | undefined;
  if (!x || !y || x.length !== 32 || y.length !== 32) {
    throw new Error("Invalid COSE P-256 key: missing x or y");
  }
  // SubjectPublicKeyInfo DER header for EC P-256 (id-ecPublicKey + prime256v1)
  const header = Buffer.from(
    "3059301306072a8648ce3d020106082a8648ce3d03010703420004",
    "hex",
  );
  return Buffer.concat([header, x, y]);
}

// ---------------------------------------------------------------------------
// DER parser helpers — extract App Attest nonce from credCert extension
// ---------------------------------------------------------------------------
// Extension OID: 1.2.840.113635.100.8.2 (Apple app-attest-attestation-nonce)
// extnValue wraps: SEQUENCE { OCTET STRING { <40-byte SHA256 nonce> } }

const ATTEST_NONCE_OID = Buffer.from("06096086480186F845010802", "hex");

function derReadLen(buf: Buffer, pos: number): [number, number] {
  const first = buf[pos++]!;
  if (first < 0x80) return [first, pos];
  const nBytes = first & 0x7f;
  let len = 0;
  for (let i = 0; i < nBytes; i++) len = (len << 8) | buf[pos++]!;
  return [len, pos];
}

function extractAttestNonce(certDer: Buffer): Buffer | null {
  // Scan the DER for our OID byte sequence
  const oidIdx = certDer.indexOf(ATTEST_NONCE_OID);
  if (oidIdx === -1) return null;
  // After the OID: BOOLEAN (optional critical flag) then OCTET STRING wrapping the value
  let pos = oidIdx + ATTEST_NONCE_OID.length;
  // Skip optional BOOLEAN critical flag (0x01 0x01 0xff)
  if (certDer[pos] === 0x01) pos += 3;
  // OCTET STRING
  if (certDer[pos] !== 0x04) return null;
  pos++;
  const [outerLen, p1] = derReadLen(certDer, pos); pos = p1;
  // Inner SEQUENCE
  if (certDer[pos] !== 0x30) return null;
  pos++;
  const [, p2] = derReadLen(certDer, pos); pos = p2;
  // [1] EXPLICIT or OCTET STRING
  // Apple wraps the nonce in: SEQUENCE { [1] { OCTET STRING { nonce } } }
  if (certDer[pos] === 0xa1) {
    pos++;
    const [, p3] = derReadLen(certDer, pos); pos = p3;
  }
  if (certDer[pos] !== 0x04) return null;
  pos++;
  const [nonceLen, p4] = derReadLen(certDer, pos); pos = p4;
  return certDer.slice(pos, pos + nonceLen);
}

// ---------------------------------------------------------------------------
// Stateless HMAC challenge tokens
// ---------------------------------------------------------------------------
// Format: <random_hex>.<hmac_hex>
// HMAC input: "<random_hex>:<floor(now/300)>" — valid for the current 5-min window
// plus the previous window (so a challenge issued at the last second isn't instantly stale).

const CHALLENGE_WINDOW_SEC = 300;

function hmacChallenge(random: string, windowTs: number): string {
  const secret = process.env.APP_ATTEST_SECRET;
  if (!secret) throw new Error("APP_ATTEST_SECRET is not set");
  return createHmac("sha256", secret).update(`${random}:${windowTs}`).digest("hex");
}

/** Issue a new HMAC-signed challenge token. */
export function issueAttestChallenge(): { token: string; expiresAt: Date } {
  const random = createHash("sha256").update(crypto.randomUUID()).digest("hex");
  const window = Math.floor(Date.now() / 1000 / CHALLENGE_WINDOW_SEC);
  const mac = hmacChallenge(random, window);
  const token = `${random}.${mac}`;
  const expiresAt = new Date((window + 1) * CHALLENGE_WINDOW_SEC * 1000);
  return { token, expiresAt };
}

/** Verify and return the raw challenge bytes (= Buffer.from(random, 'hex')). Throws on invalid/expired. */
export function verifyAttestChallenge(token: string): Buffer {
  const dot = token.indexOf(".");
  if (dot === -1) throw new Error("invalid challenge token");
  const random = token.slice(0, dot);
  const mac = token.slice(dot + 1);
  const now = Math.floor(Date.now() / 1000 / CHALLENGE_WINDOW_SEC);
  const validMacs = [hmacChallenge(random, now), hmacChallenge(random, now - 1)];
  if (!validMacs.includes(mac)) throw new Error("invalid or expired challenge token");
  return Buffer.from(random, "hex");
}

// ---------------------------------------------------------------------------
// App ID hash (used for rpIdHash verification)
// ---------------------------------------------------------------------------

function appIdHash(): Buffer {
  const teamId = process.env.APP_ATTEST_TEAM_ID;
  const bundleId = process.env.APP_ATTEST_BUNDLE_ID;
  if (!teamId || !bundleId) throw new Error("APP_ATTEST_TEAM_ID / APP_ATTEST_BUNDLE_ID not set");
  return createHash("sha256").update(`${teamId}.${bundleId}`).digest();
}

// ---------------------------------------------------------------------------
// Load Apple App Attest Root CA
// ---------------------------------------------------------------------------

let _rootCa: X509Certificate | null = null;

function getRootCa(): X509Certificate {
  if (_rootCa) return _rootCa;
  const pem = process.env.APP_ATTEST_ROOT_CA;
  if (!pem) throw new Error("APP_ATTEST_ROOT_CA not set — add the Apple App Attest Root CA G2 PEM");
  _rootCa = new X509Certificate(pem);
  return _rootCa;
}

// ---------------------------------------------------------------------------
// Attestation registration
// ---------------------------------------------------------------------------

export interface AttestationResult {
  publicKeySpki: Buffer;  // DER SubjectPublicKeyInfo — store in device_attestations
  receipt: Buffer;
  environment: "production" | "development";
  derivedKeyId: string;   // base64url(SHA256(SPKI)) — validate against iOS-supplied keyId
}

/**
 * Verify an App Attest attestation object and extract the credential key.
 * Called once at device registration (POST /v1/auth/attest/register).
 *
 * @param attestationBase64  base64-encoded CBOR attestation from DCAppAttestService
 * @param challengeToken     the token previously issued by /attest/challenge
 */
export async function verifyAttestation(
  attestationBase64: string,
  challengeToken: string,
): Promise<AttestationResult> {
  const challengeBytes = verifyAttestChallenge(challengeToken);
  const clientDataHash = createHash("sha256").update(challengeBytes).digest();

  const attestBuf = Buffer.from(attestationBase64, "base64");
  const attest = decodeCbor(attestBuf) as Record<string, CborValue>;

  const fmt = attest["fmt"] as string;
  if (fmt !== "apple-appattest") throw new Error(`unexpected fmt: ${fmt}`);

  const attStmt = attest["attStmt"] as Record<string, CborValue>;
  const x5c = attStmt["x5c"] as Buffer[];
  const receipt = attStmt["receipt"] as Buffer;
  const authData = attest["authData"] as Buffer;

  if (!Array.isArray(x5c) || x5c.length < 2) throw new Error("x5c must have at least 2 certs");

  const credCert = new X509Certificate(x5c[0]!);
  const intCert = new X509Certificate(x5c[1]!);
  const rootCa = getRootCa();

  // Verify certificate chain
  if (!intCert.verify(rootCa.publicKey as KeyObject)) throw new Error("intermediate cert not signed by root CA");
  if (!credCert.verify(intCert.publicKey as KeyObject)) throw new Error("credential cert not signed by intermediate");

  // Verify nonce in credCert matches SHA256(authData || clientDataHash)
  const expectedNonce = createHash("sha256")
    .update(authData)
    .update(clientDataHash)
    .digest();
  const certNonce = extractAttestNonce(Buffer.from(credCert.raw));
  if (!certNonce) throw new Error("nonce extension not found in credCert");
  if (!certNonce.equals(expectedNonce)) throw new Error("credCert nonce mismatch");

  // Parse authData
  const parsed = parseAuthDataFull(authData);

  // Verify RP ID hash
  const expectedRpId = appIdHash();
  if (!parsed.rpIdHash.equals(expectedRpId)) throw new Error("rpIdHash mismatch");

  // Attestation sign count must be 0
  if (parsed.signCount !== 0) throw new Error("attestation signCount must be 0");

  // Detect environment from AAGUID
  // "appattest\0\0\0\0\0\0\0" = production
  // "appattestdevelop" = development
  const aaguidStr = parsed.aaguid.toString("utf8").replace(/\0/g, "");
  const environment: "production" | "development" =
    aaguidStr === "appattestdevelop" ? "development" : "production";

  // Extract credential public key from authData (COSE) and convert to SPKI DER
  const publicKeySpki = coseP256ToDer(parsed.credentialPublicKeyRaw);

  // Derive keyId = base64url(SHA256(publicKeySpki))
  const derivedKeyId = createHash("sha256")
    .update(publicKeySpki)
    .digest()
    .toString("base64url");

  return { publicKeySpki, receipt, environment, derivedKeyId };
}

// ---------------------------------------------------------------------------
// Assertion verification
// ---------------------------------------------------------------------------

/**
 * Verify an App Attest assertion on a sensitive request.
 * Returns the new counter value; caller must advance the stored counter.
 *
 * @param assertionBase64  base64-encoded CBOR assertion from DCAppAttestService
 * @param challengeToken   the token the client used as clientData input
 * @param publicKeySpki    DER SubjectPublicKeyInfo loaded from device_attestations
 * @param previousCounter  stored counter; assertion counter must be strictly greater
 */
export async function verifyAssertion(
  assertionBase64: string,
  challengeToken: string,
  publicKeySpki: Buffer,
  previousCounter: number,
): Promise<{ counter: number }> {
  const challengeBytes = verifyAttestChallenge(challengeToken);
  const clientDataHash = createHash("sha256").update(challengeBytes).digest();

  const assertBuf = Buffer.from(assertionBase64, "base64");
  const assertion = decodeCbor(assertBuf) as Record<string, CborValue>;

  const signature = assertion["signature"] as Buffer;
  const authenticatorData = assertion["authenticatorData"] as Buffer;

  if (!Buffer.isBuffer(signature) || !Buffer.isBuffer(authenticatorData)) {
    throw new Error("assertion missing signature or authenticatorData");
  }

  // Parse authenticatorData
  const parsed = parseAuthDataBase(authenticatorData);

  // Verify RP ID hash
  const expectedRpId = appIdHash();
  if (!parsed.rpIdHash.equals(expectedRpId)) throw new Error("rpIdHash mismatch");

  // Counter must advance (replay protection)
  if (parsed.signCount <= previousCounter) {
    throw new Error(`assertion counter ${parsed.signCount} not greater than stored ${previousCounter}`);
  }

  // Verify ECDSA-P256 signature over SHA256(authenticatorData || clientDataHash)
  const nonce = createHash("sha256").update(authenticatorData).update(clientDataHash).digest();
  const key = createPublicKey({ key: publicKeySpki, format: "der", type: "spki" });
  const ok = createVerify("SHA256").update(nonce).verify(key, signature);
  if (!ok) throw new Error("assertion signature verification failed");

  return { counter: parsed.signCount };
}
