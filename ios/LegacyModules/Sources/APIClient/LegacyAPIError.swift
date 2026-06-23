import Foundation

/// Errors surfaced by `LegacyAPIClient`, aligned to the API contract's error envelope
/// and status-code table (`api-contract.md §1.3–1.4`).
///
/// iOS switches on these cases (and the contract `code` strings), never on `message`.
public enum LegacyAPIError: Error, Sendable, Equatable {
    /// 401 — `unauthorized` | `token_expired` | `clock_skew`. Caller routes to auth flow.
    /// Phase 1 has no refresh token, so there is no silent retry.
    case unauthorized(code: String)
    /// 400 / 422 — malformed or semantically invalid request.
    case invalidRequest(code: String, message: String)
    /// 403 — authenticated but not allowed (`forbidden`, `age_restricted`).
    case forbidden(code: String, message: String)
    /// 404 — not found (also used to avoid leaking existence).
    case notFound
    /// 409 — conflict (`cooldown_active`, …).
    case conflict(code: String, message: String)
    /// 423 — proximity/dwell/seal/condition not satisfied
    /// (`not_in_range`, `dwell_required`, `sealed`, `condition_unmet`).
    case locked(code: String, message: String, info: LockedInfo)
    /// 429 — rate limited. `retryAfter` parsed from the `Retry-After` header when present.
    case rateLimited(retryAfter: TimeInterval?)
    /// 5xx — server error.
    case server(statusCode: Int)
    /// Response body could not be decoded into the expected type.
    case decoding
    /// Transport-level failure (no connectivity, TLS, timeout, …).
    case transport(String)
    /// Response was not an HTTP response or had an unexpected status.
    case invalidResponse(statusCode: Int)

    /// True for transport failures where retry may succeed once connectivity returns.
    public var isConnectivityFailure: Bool {
        if case .transport = self { return true }
        return false
    }

    /// True when backend rejected a protected request due to missing/invalid App Attest proof.
    public var isAppAttestFailure: Bool {
        switch self {
        case .unauthorized(let code), .forbidden(let code, _):
            return [
                "attestation_required",
                "attestation_invalid",
                "attestation_mismatch",
                "attestation_replay",
                "attestation_untrusted",
                "attestation_stale",
            ].contains(code)
        default:
            return false
        }
    }
}

/// Extra body fields carried on `423 Locked` responses (contract §4).
public struct LockedInfo: Sendable, Equatable {
    public let retryAfterSeconds: Int?
    public let opensAt: Date?
    public let fallbackAt: Date?

    public init(retryAfterSeconds: Int? = nil, opensAt: Date? = nil, fallbackAt: Date? = nil) {
        self.retryAfterSeconds = retryAfterSeconds
        self.opensAt = opensAt
        self.fallbackAt = fallbackAt
    }

    public static let empty = LockedInfo()
}

/// Wire shape of the standard error envelope: `{ "error": { code, message, request_id } }`.
struct APIErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
        let requestID: String?

        enum CodingKeys: String, CodingKey {
            case code, message
            case requestID = "request_id"
        }
    }

    let error: Body
}

/// Locked-response extra fields, decoded best-effort from the same body.
struct LockedBody: Decodable {
    let retryAfterS: Int?
    let opensAt: String?
    let fallbackAt: String?

    enum CodingKeys: String, CodingKey {
        case retryAfterS = "retry_after_s"
        case opensAt = "opens_at"
        case fallbackAt = "fallback_at"
    }
}
