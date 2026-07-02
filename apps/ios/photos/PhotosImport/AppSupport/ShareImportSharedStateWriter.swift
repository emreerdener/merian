import Foundation

@MainActor
enum ShareImportSharedStateWriter {
    static func refresh() {
        ShareImportSharedSettingsStore.write(
            ShareImportSettingsSnapshot(
                generatedAt: Date(),
                requiresScanConfirmation: AppSettings.shared.requiresScanConfirmation,
                isProActive: RevenueCatManager.shared.isProActive,
                freeScansRemaining: UsageManager.shared.freeScansRemaining,
                alphaUnlimitedFreeScansEnabled: MerianConfig.alphaUnlimitedFreeScansEnabled
            )
        )
    }
}
