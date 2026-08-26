struct FieldTripPublishEndpoint<Output> {
    let isAvailable: Bool
    let publish: @MainActor (_ title: String, _ description: String) async throws -> Output

    static var unavailable: Self {
        Self(isAvailable: false) { _, _ in
            throw CancellationError()
        }
    }
}

extension FieldTripPublishEndpoint where Output == FieldTripPublicationDetail {
    static func outing(userFieldTripId: String) -> Self {
        Self(
            isAvailable: true,
            publish: { title, description in
                try await MerianNetworkClient.shared.publishFieldTrip(
                    userFieldTripId: userFieldTripId,
                    title: title,
                    description: description
                )
            }
        )
    }
}

extension FieldTripPublishEndpoint where Output == FieldTripChallengeEntryDetail {
    static func eventEntry(participationId: String) -> Self {
        Self(
            isAvailable: true,
            publish: { title, description in
                try await MerianNetworkClient.shared.publishFieldTripChallengeEntry(
                    participationId: participationId,
                    title: title,
                    description: description
                )
            }
        )
    }
}
