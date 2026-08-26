extension FieldTripsViewModel.Dependencies {
    static let live = Self(
        loadTemplates: {
            try await MerianNetworkClient.shared.getFieldTrips(userRegion: $0)
        },
        loadChallenges: {
            try await MerianNetworkClient.shared.getFieldTripChallenges(userRegion: $0)
        },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension FieldTripTemplateDetailViewModel.Dependencies {
    static let live = Self(
        loadById: {
            try await MerianNetworkClient.shared.getFieldTripTemplate(templateId: $0)
        },
        loadBySlug: {
            try await MerianNetworkClient.shared.getFieldTripTemplate(slug: $0)
        },
        start: {
            try await MerianNetworkClient.shared.startFieldTrip(templateId: $0)
        },
        stop: {
            try await MerianNetworkClient.shared.stopFieldTrip(userFieldTripId: $0)
        },
        reset: {
            try await MerianNetworkClient.shared.resetFieldTrip(userFieldTripId: $0)
        },
        loadCommunity: {
            try await MerianNetworkClient.shared.getFieldTripCommunityPublications(
                mode: .smart,
                templateId: $0,
                userRegion: nil,
                limit: 3
            )
        },
        successFeedback: { HapticManager.shared.triggerSuccessPulse() },
        errorFeedback: { HapticManager.shared.triggerErrorThump() },
        progressDidChange: {
            AppDIContainer.shared.appEventPublisher.send(
                .captureGoalContextInvalidated(source: .fieldTrip)
            )
        },
        detailErrorMessage: {
            ExploreErrorFormatter.fieldTripDetailMessage(for: $0)
        },
        mutationErrorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension FieldTripChallengeDetailViewModel.Dependencies {
    static let live = Self(
        loadChallenge: { challengeId, entriesLimit in
            try await MerianNetworkClient.shared.getFieldTripChallenge(
                challengeId: challengeId,
                entriesLimit: entriesLimit
            )
        },
        joinChallenge: {
            try await MerianNetworkClient.shared.joinFieldTripChallenge(
                challengeId: $0
            )
        },
        loadEntriesPage: { request in
            try await MerianNetworkClient.shared.getFieldTripChallengePublications(
                challengeId: request.challengeId,
                limit: request.limit,
                beforePublishedAt: request.beforePublishedAt,
                beforeEntryId: request.beforeEntryId
            )
        },
        successFeedback: { HapticManager.shared.triggerSuccessPulse() },
        errorFeedback: { HapticManager.shared.triggerErrorThump() },
        progressDidChange: {
            AppDIContainer.shared.appEventPublisher.send(
                .captureGoalContextInvalidated(source: .fieldTrip)
            )
        },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension ActiveFieldTripsProfileViewModel.Dependencies {
    static func live(
        earnedPatchesDidChange: @escaping ([EarnedFieldTripPatch]) -> Void,
        loadingDidChange: @escaping (Bool) -> Void
    ) -> Self {
        Self(
            loadTemplates: {
                try await MerianNetworkClient.shared.getFieldTrips(limit: $0)
            },
            earnedPatchesDidChange: earnedPatchesDidChange,
            loadingDidChange: loadingDidChange
        )
    }
}
