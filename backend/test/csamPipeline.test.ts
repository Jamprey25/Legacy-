import { afterEach, describe, expect, it } from "vitest";
import {
  assertScanClearAllowed,
  csamPipelineMode,
  isDevStubPipeline,
  isProductionEnvironment,
} from "../src/lib/csamPipeline.js";
import { ApiError } from "../src/lib/errors.js";

describe("csamPipeline", () => {
  const env = process.env;

  afterEach(() => {
    process.env = { ...env };
  });

  it("defaults to stub pipeline mode", () => {
    delete process.env.CSAM_PIPELINE;
    expect(csamPipelineMode()).toBe("stub");
  });

  it("allows clear in dev stub mode", () => {
    process.env.NODE_ENV = "development";
    process.env.CSAM_PIPELINE = "stub";
    expect(isDevStubPipeline()).toBe(true);
    expect(() => assertScanClearAllowed()).not.toThrow();
  });

  it("blocks clear in production stub mode", () => {
    process.env.NODE_ENV = "production";
    process.env.CSAM_PIPELINE = "stub";
    expect(isProductionEnvironment()).toBe(true);
    expect(isDevStubPipeline()).toBe(false);
    try {
      assertScanClearAllowed();
      expect.fail("expected throw");
    } catch (err) {
      expect(err).toBeInstanceOf(ApiError);
      expect((err as ApiError).code).toBe("internal_error");
    }
  });
});
