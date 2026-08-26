import Foundation
import Observation

@MainActor
@Observable
final class FieldTripPublishViewModel<Output> {
    struct Dependencies {
        let endpoint: FieldTripPublishEndpoint<Output>
        let successFeedback: @MainActor () -> Void
        let errorFeedback: @MainActor () -> Void
        let errorMessage: @MainActor (Error) -> String

        static func live(endpoint: FieldTripPublishEndpoint<Output>) -> Self {
            Self(
                endpoint: endpoint,
                successFeedback: { HapticManager.shared.triggerSuccessPulse() },
                errorFeedback: { HapticManager.shared.triggerErrorThump() },
                errorMessage: { ExploreErrorFormatter.message(for: $0) }
            )
        }
    }

    var title: String
    var description = ""
    var isPublishing = false
    var errorMessage: String?

    private let dependencies: Dependencies

    init(
        initialTitle: String,
        endpoint: FieldTripPublishEndpoint<Output>
    ) {
        title = initialTitle
        dependencies = .live(endpoint: endpoint)
    }

    init(initialTitle: String, dependencies: Dependencies) {
        title = initialTitle
        self.dependencies = dependencies
    }

    var canPublish: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func publish() async -> Output? {
        guard canPublish,
              !isPublishing,
              dependencies.endpoint.isAvailable else { return nil }
        isPublishing = true
        errorMessage = nil
        defer { isPublishing = false }

        do {
            let output = try await dependencies.endpoint.publish(title, description)
            dependencies.successFeedback()
            return output
        } catch {
            dependencies.errorFeedback()
            errorMessage = dependencies.errorMessage(error)
            return nil
        }
    }
}
