// Error envelope per api-contract.md §1.3 / §1.4.
// Every non-2xx response is { error: { code, message, request_id, ...extra } }.

import type { Context } from "hono";

export type ErrorCode =
  | "invalid_request"
  | "invalid_coordinates"
  | "unauthorized"
  | "token_expired"
  | "clock_skew"
  | "forbidden"
  | "age_restricted"
  | "not_found"
  | "cooldown_active"
  | "cannot_elevate_import"
  | "seal_config_invalid"
  | "not_in_range"
  | "dwell_required"
  | "sealed"
  | "condition_unmet"
  | "rate_limited"
  | "invalid_code"
  | "dob_required"
  | "internal_error";

const STATUS_BY_CODE: Record<ErrorCode, number> = {
  invalid_request: 400,
  invalid_coordinates: 400,
  unauthorized: 401,
  token_expired: 401,
  clock_skew: 401,
  forbidden: 403,
  age_restricted: 403,
  not_found: 404,
  cooldown_active: 409,
  cannot_elevate_import: 422,
  seal_config_invalid: 422,
  not_in_range: 423,
  dwell_required: 423,
  sealed: 423,
  condition_unmet: 423,
  rate_limited: 429,
  invalid_code: 401,
  dob_required: 400,
  internal_error: 500,
};

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  readonly extra: Record<string, unknown>;

  /**
   * @param statusOverride  Optional HTTP status code override (default: looked up from code).
   *                        Pass when the caller wants to be explicit (e.g. 423 for proximity errors).
   */
  constructor(
    code: ErrorCode,
    message: string,
    statusOrExtra: number | Record<string, unknown> = {},
    extra: Record<string, unknown> = {},
  ) {
    super(message);
    this.code = code;
    if (typeof statusOrExtra === "number") {
      this.status = statusOrExtra;
      this.extra = extra;
    } else {
      this.status = STATUS_BY_CODE[code];
      this.extra = statusOrExtra;
    }
  }
}

/** Hono onError handler — serializes ApiError (and unknowns) to the envelope. */
export function errorHandler(err: Error, c: Context): Response {
  const requestId = c.get("requestId") ?? "unknown";

  if (err instanceof ApiError) {
    return c.json(
      { error: { code: err.code, message: err.message, request_id: requestId, ...err.extra } },
      err.status as 400,
    );
  }

  // Never leak internals.
  console.error(`[${requestId}] unhandled`, err);
  return c.json(
    { error: { code: "internal_error", message: "Something went wrong.", request_id: requestId } },
    500,
  );
}
