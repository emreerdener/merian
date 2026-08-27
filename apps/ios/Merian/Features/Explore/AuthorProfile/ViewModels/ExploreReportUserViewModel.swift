import Observation

@MainActor
@Observable
final class ExploreReportUserViewModel {
    struct Dependencies {
        let reportUser: @MainActor (
            _ reportedUserId: String,
            _ reason: ExploreUserReportReason,
            _ details: String?
        ) async throws -> Void
        let successFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let errorMessage: @MainActor (Error) -> String
    }

    static let detailsLimit = 1_000

    var reason = ExploreUserReportReason.spam
    private(set) var details = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    private let dependencies: Dependencies

    init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    func updateDetails(_ value: String) {
        details = String(value.prefix(Self.detailsLimit))
    }

    func submit(reportedUserId: String) async -> Bool {
        guard !isSubmitting else { return false }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await dependencies.reportUser(reportedUserId, reason, details)
            guard !Task.isCancelled else { return false }
            dependencies.successFeedback()
            return true
        } catch {
            guard !Task.isCancelled else { return false }
            dependencies.errorFeedback()
            errorMessage = dependencies.errorMessage(error)
            return false
        }
    }
}
