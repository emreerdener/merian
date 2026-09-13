import Foundation

extension ConsentMutationService.Dependencies {
    @MainActor
    static let live = Self(
        now: Date.init,
        makeUUID: UUID.init,
        appVersion: {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0"
        },
        appBuild: {
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "0"
        }
    )
}
