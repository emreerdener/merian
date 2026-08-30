@MainActor
struct SettingsExportDependencies {
    let requestPersonalExport: @MainActor () async throws -> Void
    let logUnexpectedFailure: @MainActor (_ error: Error) -> Void

    static var live: Self {
        Self(
            requestPersonalExport: {
                try await MerianNetworkClient.shared.requestDwcAExport(
                    scope: "personal"
                )
            },
            logUnexpectedFailure: { error in
                MerianLog.network.error(
                    "DwC-A export request failed: \(error, privacy: .private)"
                )
            }
        )
    }
}
