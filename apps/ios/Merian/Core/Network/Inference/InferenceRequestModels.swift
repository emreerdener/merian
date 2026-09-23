import Foundation

/// Immutable environment values embedded in an inference request body.
/// Auth leases and mutable session state never cross this boundary.
struct InferencePayloadContext: Sendable {
    let userId: String
    let deviceLocale: String
    let deviceTimeZone: String
    let deviceRegion: String?
    let currentMonth: Int
    let timeOfDay: String
    let depthScaleText: String?
    let defaultGeoprivacy: String
}

struct AuthenticatedInferenceRequest: Sendable {
    let request: URLRequest
    let expectedAuthUserID: UUID

    /// Keeps the serialized inference body, JWT, and eventual transport lease
    /// attached to the same Auth account across suspensions.
    func isBound(to session: AuthTransitionSession) -> Bool {
        expectedAuthUserID == session.userID
    }
}

/// Process-local proof of the serialized fixed-context request and its live owner.
/// Never persisted, placed in headers, or attached by background request builders.
struct IdentificationMeasurementContext: Sendable {
    typealias Validator = @MainActor @Sendable () throws -> Void
    private let validateAttempt: Validator

    static func fixedAudio(
        body: Data?, telemetry: CaptureTelemetry, validateAttempt: Validator?
    ) -> Self? {
        #if DEBUG && targetEnvironment(simulator)
        guard telemetry.debugReplayProfile == .audioMinimalV1,
              let validateAttempt, let body,
              let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              Set(payload.keys) == [
                "user_id", "client_scan_id", "geoprivacy", "mimeType",
                "deviceLocale", "deviceTimeZone", "currentMonth", "timeOfDay",
                "audioBase64s", "audioMediaItems", "ownerMediaTimeline"
              ],
              payload["deviceLocale"] as? String == "en",
              payload["deviceTimeZone"] as? String == "UTC",
              payload["currentMonth"] as? Int == 1,
              payload["timeOfDay"] as? String == "12:00 PM",
              let audio = payload["audioBase64s"] as? [String],
              audio.count == 1, !audio[0].isEmpty,
              let descriptors = payload["audioMediaItems"] as? [[String: Any]],
              NSArray(array: descriptors).isEqual(to: [IdentifyAudioMediaItem.audio(sourceIndex: 0).jsonObject]),
              let timeline = payload["ownerMediaTimeline"] as? [[String: Any]],
              NSArray(array: timeline).isEqual(to: [IdentifyOwnerMediaTimelineItem.audio(audioInputIndex: 0, sourceIndex: 0).jsonObject])
        else { return nil }
        return Self(validateAttempt: validateAttempt)
        #else
        return nil
        #endif
    }

    @MainActor
    func isCurrent() -> Bool {
        guard !Task.isCancelled else { return false }
        do {
            try validateAttempt()
            return true
        } catch {
            return false
        }
    }
}
