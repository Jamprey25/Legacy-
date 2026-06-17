// Storage abstraction — generates signed PUT/GET URLs for media assets.
//
// The concrete backend (Vercel Blob, R2, or S3) is selected by env var STORAGE_BACKEND.
// In dev/CI with no credentials, falls back to a stub that returns placeholder URLs.
//
// Joseph: set STORAGE_BACKEND=vercel-blob | r2 | s3 in .env.local and add the
// corresponding credentials. See .env.example for the required vars per backend.
// Decision pending — leaving stub active until backend is chosen (collab-log.md).

const BACKEND = process.env.STORAGE_BACKEND ?? "stub";
const TTL_SECONDS = 15 * 60; // 15-min signed URL window (api-contract §3.1)

export interface SignedPutResult {
  mediaKey: string;
  signedPutUrl: string;
  expiresAt: string; // ISO-8601
}

/** Generate a signed PUT URL for a new media upload. */
export async function generateSignedPutUrl(
  memoryId: string,
  mediaType: "photo" | "video" | "text",
): Promise<SignedPutResult> {
  const ext = mediaType === "video" ? "mp4" : "jpg";
  const mediaKey = `memories/${memoryId}/original.${ext}`;
  const expiresAt = new Date(Date.now() + TTL_SECONDS * 1000).toISOString();

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
