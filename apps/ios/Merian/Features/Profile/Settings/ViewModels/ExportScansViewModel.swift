import Foundation
import Observation

@MainActor
@Observable
final class ExportScansViewModel {
    private(set) var hasRequestedExport = false
    private(set) var isRequesting = false
    var errorMessage: String?

    private let dependencies: SettingsExportDependencies

    init(dependencies: SettingsExportDependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    func requestExport() async -> Bool {
        guard !hasRequestedExport, !isRequesting else { return false }
        isRequesting = true
        defer { isRequesting = false }

        do {
            try await dependencies.requestPersonalExport()
            return true
        } catch let error as MerianError {
            if case .httpError(let statusCode, _) = error,
               statusCode == 429 {
                errorMessage =
                    "You can only generate one Darwin Core Archive every 24 hours. Your most recent export was already emailed to you."
            } else {
                errorMessage =
                    "Failed to queue export. Please try again later."
            }
            return false
        } catch {
            dependencies.logUnexpectedFailure(error)
            errorMessage = "An unexpected error occurred."
            return false
        }
    }

    func presentSuccessfulRequest() {
        hasRequestedExport = true
    }
}
