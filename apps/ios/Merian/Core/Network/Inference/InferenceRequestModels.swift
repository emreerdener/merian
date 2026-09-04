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
