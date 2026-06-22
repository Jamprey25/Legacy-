import CryptoKit
import Foundation

/// Shared challenge hashing for App Attest (matches backend `appAttest.ts`).
public enum AppAttestChallenge {
    public static func clientDataHash(for challengeToken: String) throws -> Data {
        guard let dot = challengeToken.firstIndex(of: ".") else {
            throw AppAttestChallengeError.invalidToken
        }
        let randomHex = String(challengeToken[..<dot])
        guard let randomBytes = Data(hexString: randomHex) else {
            throw AppAttestChallengeError.invalidToken
        }
        return Data(SHA256.hash(data: randomBytes))
    }
}

public enum AppAttestChallengeError: Error {
    case invalidToken
}

extension Data {
    init?(hexString: String) {
        let trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: trimmed.count / 2)
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let next = trimmed.index(index, offsetBy: 2)
            guard next <= trimmed.endIndex else { return nil }
            let byte = trimmed[index..<next]
            guard let value = UInt8(byte, radix: 16) else { return nil }
            data.append(value)
            index = next
        }
        self = data
    }
}
