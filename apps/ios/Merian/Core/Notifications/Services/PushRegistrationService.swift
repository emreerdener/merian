@MainActor
struct PushRegistrationService {
    let register:
        @MainActor (_ request: PushRegistrationRequest) async throws -> Void

    static var live: Self {
        Self(
            register: { request in
                try await MerianNetworkClient.shared.registerPushDevice(
                    deviceToken: request.deviceToken,
                    environment: request.environment,
                    exploreEnabled: request.exploreEnabled,
                    commentMentionsEnabled: request.commentMentionsEnabled,
                    communityIdentificationsEnabled:
                        request.communityIdentificationsEnabled
                )
            }
        )
    }
}
