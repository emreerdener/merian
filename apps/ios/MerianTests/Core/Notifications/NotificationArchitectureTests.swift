import Foundation
import Testing

@Suite("Core Notifications architecture")
struct NotificationArchitectureTests {
    @Test("Live effects remain in notification services")
    func liveEffectsRemainInServices() throws {
        let root = try repositoryRoot()
        let sourceRoot = root.appendingPathComponent(Self.sourceRoot)
        let swiftFiles = try productionSwiftFiles(in: sourceRoot)

        for file in swiftFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let isService = file.path.contains("/Services/")
            if !isService {
                for forbidden in [
                    "MerianNetworkClient.shared",
                    "SupabaseManager.shared",
                    "UNUserNotificationCenter.current()",
                    "UIApplication.shared",
                    "UserDefaults.standard"
                ] {
                    #expect(
                        !contents.contains(forbidden),
                        "\(file.lastPathComponent) owns live effect \(forbidden)"
                    )
                }
            }
        }
    }

    @Test("System and endpoint effects each have one owner")
    func effectsHaveSingleOwners() throws {
        let root = try repositoryRoot()
        let files = try productionSwiftFiles(
            in: root.appendingPathComponent(Self.sourceRoot)
        )

        #expect(
            try effectOwners(
                "MerianNetworkClient.shared",
                in: files
            ) == Set([
                "AppIconBadgeDependencies.swift",
                "PushRegistrationService.swift"
            ])
        )
        #expect(
            try effectOwners(
                "SupabaseManager.shared",
                in: files
            ) == Set(["PushRegistrationContextService.swift"])
        )
        #expect(
            try effectOwners(
                "UNUserNotificationCenter.current()",
                in: files
            ) == Set(["SystemNotificationCenterService.swift"])
        )
        #expect(
            try effectOwners("UIApplication.shared", in: files) ==
                Set(["SystemNotificationCenterService.swift"])
        )
        #expect(
            try effectOwners("UserDefaults.standard", in: files) == Set([
                "AppIconBadgeDependencies.swift",
                "PushNotificationPreferencesStore.swift"
            ])
        )
    }

    @Test("Account scope remains local to registration coalescing")
    func accountScopeRemainsLocal() throws {
        let models = try source(
            Self.sourceRoot + "/Models/PushNotificationModels.swift"
        )
        let service = try source(
            Self.sourceRoot +
                "/Services/PushRegistrationService.swift"
        )

        #expect(models.contains("let accountScopeID: String?"))
        #expect(!service.contains("accountScopeID"))
    }

    @Test("The live system notification center has one app-wide owner")
    func systemNotificationCenterHasOneAppWideOwner() throws {
        let root = try repositoryRoot()
        let files = try productionSwiftFiles(
            in: root.appendingPathComponent("apps/ios/Merian")
        )

        #expect(
            try effectOwners(
                "UNUserNotificationCenter.current()",
                in: files
            ) == Set(["SystemNotificationCenterService.swift"])
        )
    }

    @Test("Stable compatibility facades remain available")
    func compatibilitySurfaceRemainsStable() throws {
        let manager = try source(
            Self.sourceRoot + "/PushNotificationManager.swift"
        )
        let badge = try source(
            Self.sourceRoot + "/AppIconBadgeCoordinator.swift"
        )

        for declaration in [
            "func setupDelegate()",
            "func syncPermissionState()",
            "func requestAuthorization(",
            "func registerForRemoteNotificationsIfAuthorized()",
            "func handleRemoteDeviceToken(_ deviceToken: Data)",
            "func syncRemotePushRegistrationIfPossible(reason: String)",
            "func sendInferenceCompleteNotification(",
            "func sendUploadFailedNotification()",
            "func sendAchievementUnlockedNotification(",
            "func setBadgeCount(_ count: Int)"
        ] {
            #expect(manager.contains(declaration))
        }
        for declaration in [
            "static var exploreUnreadNotificationCount: Int",
            "static func setExploreUnreadNotificationCount(_ count: Int)",
            "static func clearExploreUnreadNotificationCount()",
            "static func refreshExploreUnreadNotificationCount(",
            "static func resetAccountState()",
            "static func updateAppIconBadge()"
        ] {
            #expect(badge.contains(declaration))
        }
    }

    @Test("Every production notification file stays reviewable")
    func filesRemainBelowLineCeiling() throws {
        let root = try repositoryRoot()
        let sourceRoot = root.appendingPathComponent(Self.sourceRoot)
        for file in try productionSwiftFiles(in: sourceRoot) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(
                lineCount(contents) <= 400,
                "\(file.lastPathComponent) exceeds 400 lines"
            )
        }
    }

    @Test("Hardware and utility aggregate owners are retired")
    func aggregateOwnersAreRetired() throws {
        let root = try repositoryRoot()
        for path in Self.retiredPaths {
            #expect(
                !FileManager.default.fileExists(
                    atPath: root.appendingPathComponent(path).path
                )
            )
        }

        #expect(!FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                "apps/ios/Merian/Core/UI/Components/" +
                    "PostIdentificationNotificationSheetView.swift"
            ).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                Self.sourceRoot +
                    "/Views/PostIdentificationNotificationSheetView.swift"
            ).path
        ))
    }

    private func source(_ path: String) throws -> String {
        let file = try repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private func productionSwiftFiles(in directory: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: Set(keys)).isRegularFile ==
                  true else { return nil }
            return url
        }
    }

    private func effectOwners(
        _ token: String,
        in files: [URL]
    ) throws -> Set<String> {
        try Set(files.compactMap { file in
            let contents = try String(contentsOf: file, encoding: .utf8)
            return contents.contains(token) ? file.lastPathComponent : nil
        })
    }

    private func lineCount(_ source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static let sourceRoot =
        "apps/ios/Merian/Core/Notifications"
    private static let retiredPaths = [
        "apps/ios/Merian/Core/Hardware/PushNotificationManager.swift",
        "apps/ios/MerianTests/Core/Hardware/PushNotificationManagerTests.swift",
        "apps/ios/MerianTests/Core/Hardware/AppIconBadgeCoordinatorTests.swift",
        "apps/ios/MerianTests/Core/Utilities/PushNotificationRoutingTests.swift"
    ]
}
