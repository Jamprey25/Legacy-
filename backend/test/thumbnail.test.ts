// Thumbnail resize (csam-thumbnail-generation). Tests the pure resize step with a
// generated source image — no network/Blob needed.

import { describe, it, expect } from "vitest";
import sharp from "sharp";
import { resizeToThumbnail } from "../src/lib/thumbnail.js";

describe("resizeToThumbnail", () => {
  it("downscales a large image to <= 400px wide WebP", async () => {
    // Generate a 1200x800 red JPEG as the source.
    const source = await sharp({
      create: { width: 1200, height: 800, channels: 3, background: { r: 200, g: 30, b: 30 } },
    })
      .jpeg()
      .toBuffer();

    const thumb = await resizeToThumbnail(source);
    const meta = await sharp(thumb).metadata();

    expect(meta.format).toBe("webp");
    expect(meta.width).toBe(400);
    expect(thumb.length).toBeLessThan(source.length); // compressed
  });

  it("does not enlarge an already-small image", async () => {
    const source = await sharp({
      create: { width: 100, height: 100, channels: 3, background: { r: 0, g: 0, b: 0 } },
    })
      .png()
      .toBuffer();

    const thumb = await resizeToThumbnail(source);
    const meta = await sharp(thumb).metadata();

    expect(meta.width).toBe(100); // withoutEnlargement
    expect(meta.format).toBe("webp");
  });

  it("strips metadata (no EXIF in the thumbnail)", async () => {
    const source = await sharp({
      create: { width: 500, height: 500, channels: 3, background: { r: 10, g: 10, b: 10 } },
    })
      .withMetadata({ exif: { IFD0: { Copyright: "test" } } })
      .jpeg()
      .toBuffer();

    const thumb = await resizeToThumbnail(source);
    const meta = await sharp(thumb).metadata();

    expect(meta.exif).toBeUndefined();
  });
});
