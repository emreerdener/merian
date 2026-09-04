import Foundation

enum EdgeFunctionErrorPolicy {
    private struct Payload: Decodable {
        let code: String?
        let error: String?
        let message: String?
    }

    static func isRefreshableAuthSessionError(
        responseData: Data,
        fallbackMessage: String
    ) -> Bool {
        if let payload = try? JSONDecoder().decode(
            Payload.self,
            from: responseData
        ) {
            if payload.code == "auth_session_missing"
                || payload.code == "invalid_session_token" {
                return true
            }

            if payload.error?.localizedCaseInsensitiveContains(
                "Auth session missing"
            ) == true
                || payload.error?.localizedCaseInsensitiveContains(
                    "Invalid or expired session token"
                ) == true {
                return true
            }
        }

        return fallbackMessage.localizedCaseInsensitiveContains(
            "Auth session missing"
        )
            || fallbackMessage.localizedCaseInsensitiveContains(
                "Invalid or expired session token"
            )
    }

    static func reportsMissingFunction(responseData: Data) -> Bool {
        guard let payload = try? JSONDecoder().decode(
            Payload.self,
            from: responseData
        ) else {
            return false
        }
        return payload.code?.caseInsensitiveCompare("NOT_FOUND") == .orderedSame
            || payload.message?.localizedCaseInsensitiveContains(
                "Requested function was not found"
            ) == true
            || payload.error?.localizedCaseInsensitiveContains(
                "Requested function was not found"
            ) == true
    }

    static func stableCode(responseData: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(
            Payload.self,
            from: responseData
        ),
              let rawCode = payload.code?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              rawCode.range(
                of: #"^[a-z][a-z0-9_]{1,63}$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }
        return rawCode
    }

    static func stableCode(from error: Error) -> String? {
        guard case let MerianError.httpError(_, message) = error else {
            return nil
        }
        return stableCode(responseData: Data(message.utf8))
    }
}
