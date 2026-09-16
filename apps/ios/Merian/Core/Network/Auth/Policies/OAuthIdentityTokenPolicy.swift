import Foundation

enum OAuthIdentityTokenPolicy {
    nonisolated static func providerSubject(
        from idToken: String
    ) throws -> String {
        let segments = idToken.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard segments.count == 3 else {
            throw SupabaseAuthTransitionError.invalidOAuthIdentityToken
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - payload.count % 4) % 4
        payload.append(String(repeating: "=", count: padding))

        guard let data = Data(base64Encoded: payload),
              let object = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let subject = object["sub"] as? String else {
            throw SupabaseAuthTransitionError.invalidOAuthIdentityToken
        }

        let normalizedSubject = subject.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedSubject.isEmpty,
              normalizedSubject.count <= 255,
              normalizedSubject.rangeOfCharacter(
                  from: .controlCharacters
              ) == nil else {
            throw SupabaseAuthTransitionError.invalidOAuthIdentityToken
        }
        return normalizedSubject
    }
}
