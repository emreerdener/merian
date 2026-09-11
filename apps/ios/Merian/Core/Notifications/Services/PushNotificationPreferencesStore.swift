import Foundation

@MainActor
struct PushNotificationPreferencesStore {
    struct Dependencies {
        let string: @MainActor (_ key: String) -> String?
        let bool: @MainActor (_ key: String) -> Bool
        let setString: @MainActor (_ value: String, _ key: String) -> Void
        let setBool: @MainActor (_ value: Bool, _ key: String) -> Void

        static var live: Self {
            Self(
                string: { UserDefaults.standard.string(forKey: $0) },
                bool: { UserDefaults.standard.bool(forKey: $0) },
                setString: { value, key in
                    UserDefaults.standard.set(value, forKey: key)
                },
                setBool: { value, key in
                    UserDefaults.standard.set(value, forKey: key)
                }
            )
        }
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies? = nil) {
        self.dependencies = dependencies ?? .live
    }

    nonisolated static func suppressesInferenceBanners() -> Bool {
        UserDefaults.standard.bool(
            forKey: UserDefaultsKeys.suppressInferenceBanners
        )
    }

    var hasAuthorization: Bool {
        dependencies.bool(UserDefaultsKeys.hasPushNotificationAuthorization)
    }

    func setAuthorization(_ isGranted: Bool) {
        guard hasAuthorization != isGranted else { return }
        dependencies.setBool(
            isGranted,
            UserDefaultsKeys.hasPushNotificationAuthorization
        )
    }

    func storeDeviceToken(_ deviceToken: String) {
        dependencies.setString(
            deviceToken,
            UserDefaultsKeys.remotePushDeviceToken
        )
    }

    func registrationRequest(
        accountScopeID: String?,
        environment: String
    ) -> PushRegistrationRequest? {
        PushNotificationPolicy.registrationRequest(
            accountScopeID: accountScopeID,
            deviceToken: dependencies.string(
                UserDefaultsKeys.remotePushDeviceToken
            ),
            environment: environment,
            hasAuthorization: hasAuthorization,
            exploreEnabled: dependencies.bool(
                UserDefaultsKeys.isExploreNotificationsEnabled
            ),
            commentMentionsEnabled: dependencies.bool(
                UserDefaultsKeys.isExploreCommentMentionNotificationsEnabled
            ),
            communityIdentificationsEnabled: dependencies.bool(
                UserDefaultsKeys.isCommunityIdentificationNotificationsEnabled
            )
        )
    }
}
