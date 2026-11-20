import CryptoKit
import Foundation

extension MerianEnvironment {
    /// Local packet validation only. These references do not verify hosted state,
    /// authorize execution, or establish the trustworthiness of an activation packet.
    struct HistoryQualificationIdentityEvidence: Sendable, Equatable, Codable {
        let approvalID: UUID
        let host: String
        let provider: String
        let accountFingerprint: String
        let subjectFingerprint: String
        let mappingEvidenceDigest: String
        let refusalEvidenceDigest: String
        let mappingObservedAt: Date
        let mappingExpiresAt: Date
        let refusalObservedAt: Date
        let refusalExpiresAt: Date

        func isCurrent(at now: Date) -> Bool {
            now.timeIntervalSince1970.isFinite &&
                mappingObservedAt <= now && now < mappingExpiresAt &&
                refusalObservedAt <= now && now < refusalExpiresAt
        }

        func isBound(to scope: HistoryQualificationScope, at now: Date) -> Bool {
            approvalID == scope.approvalID && host == scope.host && provider == "google" &&
                scope.accountFingerprints == [accountFingerprint] && isCurrent(at: now) &&
                [subjectFingerprint, mappingEvidenceDigest, refusalEvidenceDigest].allSatisfy {
                    $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
                }
        }

        func permitsGoogleExchange(isGoogle: Bool, subject: String, at now: Date) -> Bool {
            isGoogle && matchesGoogleSubject(subject, at: now)
        }

        func permitsInstalledAccount(_ accountID: UUID, isAnonymous: Bool, at now: Date) -> Bool {
            !isAnonymous && isCurrent(at: now) &&
                accountFingerprint == HistoryQualificationScope.fingerprint(accountID)
        }

        /// Matches the exact subject bytes used by the reviewed mapping inspector.
        /// This local comparison neither authenticates a token nor permits exchange.
        func matchesGoogleSubject(_ subject: String, at now: Date) -> Bool {
            guard provider == "google", isCurrent(at: now), !subject.isEmpty,
                  subject.unicodeScalars.count <= 255,
                  subject.rangeOfCharacter(from: .controlCharacters) == nil else { return false }
            let bytes = Data(("Merian.HistoryQualification.GoogleSubject/" + subject).utf8)
            let fingerprint = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            return fingerprint == subjectFingerprint
        }
    }

    // Private build inputs are installed only after separately reviewed mapping,
    // server refusal and exact-artifact operation authorization. Never cache expiry.
    static func currentQualificationIdentityEvidence(at now: Date = Date()) -> HistoryQualificationIdentityEvidence? {
        guard let scope = historyQualificationScope else { return nil }
        return try? validateHistoryQualificationIdentityEvidence(
            info: Bundle.main.infoDictionary ?? [:], scope: scope,
            compiledMarker: isHistoryQualificationBuild, now: now)
    }

    static var permitsQualificationGooglePresentation: Bool {
        !Task.isCancelled && (!isHistoryQualificationBuild || currentQualificationIdentityEvidence() != nil)
    }

    static func requireQualificationGoogleExchange(
        isGoogle: Bool, subject: @autoclosure () throws -> String
    ) throws {
        guard isHistoryQualificationBuild else { return }
        try Task.checkCancellation()
        guard isGoogle, let evidence = currentQualificationIdentityEvidence(),
              evidence.permitsGoogleExchange(isGoogle: isGoogle, subject: try subject(), at: Date()) else {
            throw HistoryQualificationFailure.accounts
        }
    }

    @discardableResult
    static func requireQualificationGoogleAccount(_ accountID: UUID, isAnonymous: Bool) throws -> HistoryQualificationIdentityEvidence? {
        guard isHistoryQualificationBuild else { return nil }
        try Task.checkCancellation()
        guard let evidence = currentQualificationIdentityEvidence(),
              evidence.permitsInstalledAccount(accountID, isAnonymous: isAnonymous, at: Date()) else {
            throw HistoryQualificationFailure.accounts
        }
        return evidence
    }

    enum QualificationIdentityEvidenceFailure: Error, Equatable {
        case compiledMarker, binding, provenance, validity
    }

    /// The exact-target/account scope must already be validated by the existing
    /// qualification validator. No field is required for ordinary composition or
    /// approved stored-session inspection. Google exchange requires one exact account.
    static func validateHistoryQualificationIdentityEvidence(
        info: [String: Any], scope: HistoryQualificationScope,
        compiledMarker: Bool, now: Date
    ) throws -> HistoryQualificationIdentityEvidence {
        guard compiledMarker else { throw QualificationIdentityEvidenceFailure.compiledMarker }
        func value(_ suffix: String) -> String? { info["MERIAN_HISTORY_IDENTITY_" + suffix] as? String }
        guard value("APPROVAL_ID") == scope.approvalID.uuidString.lowercased(),
              value("HOST") == scope.host, value("PROVIDER") == "google",
              let account = value("ACCOUNT_FINGERPRINT"), scope.accountFingerprints == [account] else {
            throw QualificationIdentityEvidenceFailure.binding
        }
        func digest(_ suffix: String) -> String? {
            guard let result = value(suffix),
                  result.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
            return result
        }
        guard let subject = digest("SUBJECT_FINGERPRINT"),
              let mapping = digest("MAPPING_EVIDENCE_DIGEST"),
              let refusal = digest("REFUSAL_EVIDENCE_DIGEST") else {
            throw QualificationIdentityEvidenceFailure.provenance
        }
        func timestamp(_ suffix: String) -> Date? {
            guard let raw = value(suffix), let seconds = UInt64(raw), seconds > 0,
                  seconds <= 253_402_300_799, String(seconds) == raw else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        guard let mappingObserved = timestamp("MAPPING_OBSERVED_AT"),
              let mappingExpires = timestamp("MAPPING_EXPIRES_AT"),
              let refusalObserved = timestamp("REFUSAL_OBSERVED_AT"),
              let refusalExpires = timestamp("REFUSAL_EXPIRES_AT") else {
            throw QualificationIdentityEvidenceFailure.validity
        }
        let result = HistoryQualificationIdentityEvidence(
            approvalID: scope.approvalID, host: scope.host, provider: "google",
            accountFingerprint: account, subjectFingerprint: subject,
            mappingEvidenceDigest: mapping, refusalEvidenceDigest: refusal,
            mappingObservedAt: mappingObserved, mappingExpiresAt: mappingExpires,
            refusalObservedAt: refusalObserved, refusalExpiresAt: refusalExpires)
        guard result.isCurrent(at: now) else { throw QualificationIdentityEvidenceFailure.validity }
        return result
    }
}
