import Foundation

enum ToastSeverity: Sendable, Equatable {
    case information
    case success
    case warning
    case error
}

enum ToastActionID: String, Sendable, Equatable {
    case viewExplorePost
    case viewCommunityRequest
    case viewNonBiologicalScans
    case retry
    case openSettings
    case undo
}

struct ToastActionDescriptor: Sendable, Equatable {
    let id: ToastActionID
    let title: String

    static let viewExplorePost = ToastActionDescriptor(id: .viewExplorePost, title: "View")
    static let viewCommunityRequest = ToastActionDescriptor(id: .viewCommunityRequest, title: "View")
    static let viewNonBiologicalScans = ToastActionDescriptor(
        id: .viewNonBiologicalScans,
        title: "View"
    )
    static let retry = ToastActionDescriptor(id: .retry, title: "Retry")
}

/// Lightweight, view-owned feedback. Domain state and executable closures stay
/// outside the payload so replacing a toast cannot retain feature models.
struct ToastPayload: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let body: String?
    let severity: ToastSeverity
    let action: ToastActionDescriptor?

    init(
        id: UUID = UUID(),
        title: String,
        body: String? = nil,
        severity: ToastSeverity,
        action: ToastActionDescriptor? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.body = body?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        self.severity = severity
        self.action = action
    }

    static func information(
        _ message: String,
        action: ToastActionDescriptor? = nil
    ) -> ToastPayload {
        parsed(message, severity: .information, action: action)
    }

    static func success(
        _ message: String,
        action: ToastActionDescriptor? = nil
    ) -> ToastPayload {
        parsed(message, severity: .success, action: action)
    }

    static func warning(
        _ message: String,
        action: ToastActionDescriptor? = nil
    ) -> ToastPayload {
        parsed(message, severity: .warning, action: action)
    }

    static func error(
        _ message: String,
        action: ToastActionDescriptor? = nil
    ) -> ToastPayload {
        parsed(message, severity: .error, action: action)
    }

    private static func parsed(
        _ message: String,
        severity: ToastSeverity,
        action: ToastActionDescriptor?
    ) -> ToastPayload {
        let parts = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let title = parts.first else {
            return ToastPayload(
                title: message,
                severity: severity,
                action: action
            )
        }

        return ToastPayload(
            title: title,
            body: parts.count > 1 ? parts.dropFirst().joined(separator: " ") : nil,
            severity: severity,
            action: action
        )
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
