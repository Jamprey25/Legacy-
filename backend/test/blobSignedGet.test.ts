import { describe, it, expect } from "vitest";
import {
  blobAccessForKey,
  blobPathnameFromKey,
  blobPutAccess,
  isVercelBlobKey,
} from "../src/lib/blobSignedGet.js";

describe("blobSignedGet helpers", () => {
  it("defaults blob put access to private", () => {
    delete process.env.BLOB_ACCESS;
    expect(blobPutAccess()).toBe("private");
  });

  it("allows public override via BLOB_ACCESS", () => {
    process.env.BLOB_ACCESS = "public";
    expect(blobPutAccess()).toBe("public");
    delete process.env.BLOB_ACCESS;
  });

  it("detects private blob hostnames", () => {
    const url = "https://abc.private.blob.vercel-storage.com/memories/x/0.jpg";
    expect(isVercelBlobKey(url)).toBe(true);
    expect(blobAccessForKey(url)).toBe("private");
  });

  it("extracts pathname from blob URL", () => {
    const url = "https://abc.public.blob.vercel-storage.com/memories/uuid/0-abc.jpg";
    expect(blobPathnameFromKey(url)).toBe("memories/uuid/0-abc.jpg");
  });

  it("treats legacy public URLs as public access", () => {
    const url = "https://abc.public.blob.vercel-storage.com/memories/uuid/0.jpg";
    expect(blobAccessForKey(url)).toBe("public");
  });
});
