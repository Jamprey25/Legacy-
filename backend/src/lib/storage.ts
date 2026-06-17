// Storage abstraction — generates signed PUT/GET URLs for media assets.
//
// The concrete backend (Vercel Blob, R2, or S3) is selected by env var STORAGE_BACKEND.
// In dev/CI with no credentials, falls back to a stub that returns placeholder URLs.
//
// Joseph: set STORAGE_BACKEND=vercel-blob | r2 | s3 in .env.local and add the
// corresponding credentials. See .env.example for the required vars per backend.
// Decision pending — leaving stub active until backend is chosen (collab-log.md).

const BACKEND = process.env.STORAGE_BACKEND ?? "stub";
const PUT_TTL_SECONDS = 15 * 60; // 15-min upload window (api-contract §3.1)
const GET_TTL_SECONDS = 60 * 60; // 60-min media view window (api-contract §4 unlock)

export interface SignedPutResult {
  mediaKey: string;
  signedPutUrl: string;
  expiresAt: string; // ISO-8601
}

/**
 * True when the active backend uploads via a client-token handshake (Vercel Blob)
 * rather than a presigned PUT URL. In that mode POST /memories returns upload: null
 * and the client uses POST /v1/uploads instead. S3/R2/stub use presigned PUT.
 */
export function usesClientUpload(): boolean {
  return BACKEND === "vercel-blob";
}

/** Generate a signed PUT URL for a new media upload. */
export async function generateSignedPutUrl(
  memoryId: string,
  mediaType: "photo" | "video" | "text",
): Promise<SignedPutResult> {
  const ext = mediaType === "video" ? "mp4" : "jpg";
  const mediaKey = `memories/${memoryId}/original.${ext}`;
  const expiresAt = new Date(Date.now() + PUT_TTL_SECONDS * 1000).toISOString();

  if (BACKEND === "stub") {
    return {
      mediaKey,
      signedPutUrl: `https://stub.storage.example/put/${mediaKey}?expires=${expiresAt}`,
      expiresAt,
    };
  }

  if (BACKEND === "vercel-blob") {
    return vercelBlobPutUrl(mediaKey, expiresAt);
  }

  if (BACKEND === "r2") {
    return r2PutUrl(mediaKey, expiresAt);
  }

  if (BACKEND === "s3") {
    return s3PutUrl(mediaKey, expiresAt);
  }

  throw new Error(`Unknown STORAGE_BACKEND: ${BACKEND}`);
}

export interface SignedGetResult {
  signedGetUrl: string;
  expiresAt: string; // ISO-8601
}

/** Generate a signed GET URL for media retrieval (unlock). */
export async function generateSignedGetUrl(mediaKey: string): Promise<SignedGetResult> {
  const expiresAt = new Date(Date.now() + GET_TTL_SECONDS * 1000).toISOString();

  if (BACKEND === "stub") {
    return {
      signedGetUrl: `https://stub.storage.example/get/${mediaKey}?expires=${expiresAt}`,
      expiresAt,
    };
  }

  if (BACKEND === "vercel-blob") {
    return vercelBlobGetUrl(mediaKey, expiresAt);
  }

  if (BACKEND === "r2") {
    return r2GetUrl(mediaKey, expiresAt);
  }

  if (BACKEND === "s3") {
    return s3GetUrl(mediaKey, expiresAt);
  }

  throw new Error(`Unknown STORAGE_BACKEND: ${BACKEND}`);
}

// ---------------------------------------------------------------------------
// Backend implementations (filled in once Joseph decides)
// ---------------------------------------------------------------------------

async function vercelBlobPutUrl(mediaKey: string, expiresAt: string): Promise<SignedPutResult> {
  // TODO: use @vercel/blob — `put(mediaKey, { access: 'public', ... })` or
  //       the client-upload token flow for direct uploads.
  // Docs: https://vercel.com/docs/storage/vercel-blob
  throw new Error("vercel-blob backend not yet implemented. Add VERCEL_BLOB_READ_WRITE_TOKEN.");
}

async function r2PutUrl(mediaKey: string, expiresAt: string): Promise<SignedPutResult> {
  // TODO: use @aws-sdk/client-s3 + @aws-sdk/s3-request-presigner against the
  //       Cloudflare R2 endpoint (s3-compatible).
  // Env: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME
  throw new Error("R2 backend not yet implemented. Add R2 credentials.");
}

async function s3PutUrl(mediaKey: string, expiresAt: string): Promise<SignedPutResult> {
  // TODO: use @aws-sdk/client-s3 + @aws-sdk/s3-request-presigner.
  // Env: AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_BUCKET_NAME
  throw new Error("S3 backend not yet implemented. Add AWS credentials.");
}

async function vercelBlobGetUrl(mediaKey: string, expiresAt: string): Promise<SignedGetResult> {
  // Vercel Blob upload stores the full public blob URL as media_key (uploads route,
  // onUploadCompleted). The URL is an unguessable bearer capability (addRandomSuffix),
  // so we return it directly. NOTE: public blobs do not expire — `expiresAt` is the
  // client-side view window, not an enforced TTL. Revisit before public-tier (DEC-23).
  return { signedGetUrl: mediaKey, expiresAt };
}

async function r2GetUrl(_mediaKey: string, _expiresAt: string): Promise<SignedGetResult> {
  throw new Error("R2 GET backend not yet implemented.");
}

async function s3GetUrl(_mediaKey: string, _expiresAt: string): Promise<SignedGetResult> {
  throw new Error("S3 GET backend not yet implemented.");
}
