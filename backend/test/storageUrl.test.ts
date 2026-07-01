import { afterEach, describe, expect, it } from "vitest";
import {
  assertAllowedStorageUrl,
  assertMediaKeyBelongsToMemory,
} from "../src/lib/storageUrl.js";
import { ApiError } from "../src/lib/errors.js";

describe("storageUrl", () => {
  const env = process.env;

  afterEach(() => {
    process.env = { ...env };
  });

  it("allows Vercel Blob hosts", () => {
    expect(() =>
      assertAllowedStorageUrl(
        "https://abc.public.blob.vercel-storage.com/memories/uuid/0.jpg",
      ),
    ).not.toThrow();
  });

  it("rejects non-HTTPS URLs", () => {
    expect(() => assertAllowedStorageUrl("http://evil.com/x")).toThrow(ApiError);
  });

  it("rejects unknown hosts", () => {
    expect(() => assertAllowedStorageUrl("https://169.254.169.254/latest/meta-data")).toThrow(
      ApiError,
    );
  });

  it("allows stub host only when STORAGE_BACKEND=stub", () => {
    process.env.STORAGE_BACKEND = "stub";
    expect(() => assertAllowedStorageUrl("https://stub.storage.example/key")).not.toThrow();
    delete process.env.STORAGE_BACKEND;
    expect(() => assertAllowedStorageUrl("https://stub.storage.example/key")).toThrow(ApiError);
  });

  it("requires media key to contain memory id", () => {
    const memoryId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    expect(() =>
      assertMediaKeyBelongsToMemory(
        `https://x.public.blob.vercel-storage.com/memories/${memoryId}/0.jpg`,
        memoryId,
      ),
    ).not.toThrow();
    expect(() =>
      assertMediaKeyBelongsToMemory("https://x.public.blob.vercel-storage.com/other/0.jpg", memoryId),
    ).toThrow(ApiError);
  });
});
