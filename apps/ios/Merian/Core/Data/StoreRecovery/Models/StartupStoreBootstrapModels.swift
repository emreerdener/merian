import SwiftData

enum StartupStoreState: Equatable {
    case normal
    case recovered
    case safeMode
}

struct StartupRecoveryNotice: Sendable {
    let title: String
    let message: String
    let diagnosticText: String?

    init(title: String, message: String, diagnosticText: String? = nil) {
        self.title = title
        self.message = message
        self.diagnosticText = diagnosticText
    }
}

struct StartupRecoveryTelemetryEvent {
    let outcome: String
    let reason: String
    let properties: [String: String]

    init(outcome: String, reason: String, properties: [String: String] = [:]) {
        self.outcome = outcome
        self.reason = reason
        self.properties = properties
    }
}

struct ModelContainerBootstrapOutcome {
    let container: ModelContainer?
    let startupStoreState: StartupStoreState
    let startupNotice: StartupRecoveryNotice?
    let telemetryEvent: StartupRecoveryTelemetryEvent?
}
