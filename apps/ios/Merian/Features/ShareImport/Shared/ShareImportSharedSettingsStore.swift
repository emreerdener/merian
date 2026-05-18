import Foundation

struct ShareImportSettingsSnapshot: Codable, Equatable, Sendable {
    let generatedAt: Date
    let requiresScanConfirmation: Bool
    let isProActive: Bool
    let freeScansRemaining: Int
    let alphaUnlimitedFreeScansEnabled: Bool

    static let fallback = ShareImportSettingsSnapshot(
        generatedAt: .distantPast,
        requiresScanConfirmation: false,
        isProActive: false,
        freeScansRemaining: 0,
        alphaUnlimitedFreeScansEnabled: false
    )

    var canPerformScan: Bool {
        alphaUnlimitedFreeScansEnabled || isProActive || freeScansRemaining > 0
    }
}

enum ShareImportSharedSettingsStore {
    static func userDefaults() -> UserDefaults? {
        UserDefaults(suiteName: ShareImportSharedConstants.appGroupIdentifier)
    }

    static func load(userDefaults: UserDefaults? = userDefaults()) -> ShareImportSettingsSnapshot {
        guard let data = userDefaults?.data(forKey: ShareImportSharedConstants.settingsDefaultsKey),
              let snapshot = try? JSONDecoder().decode(ShareImportSettingsSnapshot.self, from: data) else {
            return .fallback
        }
        return snapshot
    }

    static func write(
        _ snapshot: ShareImportSettingsSnapshot,
        userDefaults: UserDefaults? = userDefaults()
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        userDefaults?.set(data, forKey: ShareImportSharedConstants.settingsDefaultsKey)
    }

    static func consumeSharedFreeScanIfNeeded(userDefaults: UserDefaults? = userDefaults()) {
        var snapshot = load(userDefaults: userDefaults)
        guard !snapshot.alphaUnlimitedFreeScansEnabled,
              !snapshot.isProActive,
              snapshot.freeScansRemaining > 0 else {
            return
        }

        snapshot = ShareImportSettingsSnapshot(
            generatedAt: Date(),
            requiresScanConfirmation: snapshot.requiresScanConfirmation,
            isProActive: snapshot.isProActive,
            freeScansRemaining: max(0, snapshot.freeScansRemaining - 1),
            alphaUnlimitedFreeScansEnabled: snapshot.alphaUnlimitedFreeScansEnabled
        )
        write(snapshot, userDefaults: userDefaults)
    }
}
