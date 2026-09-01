extension IdentifyDashboardViewModel.Dependencies {
    static let live = Self(
        loadRequests: { request in
            try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: request.limit,
                scope: request.filter.scope,
                group: request.filter.group,
                latitude: request.latitude,
                longitude: request.longitude,
                cursor: request.cursor
            )
        },
        loadActivity: { request in
            try await MerianNetworkClient.shared.getCommunityIdentificationActivity(
                limit: request.limit,
                scope: request.filter.scope,
                group: request.filter.group,
                cursor: request.cursor
            )
        },
        requestErrorMessage: { ExploreErrorFormatter.message(for: $0) },
        activityErrorMessage: { ExploreErrorFormatter.recentActivityMessage(for: $0) }
    )
}

extension IdentifyRequestsFeedViewModel.Dependencies {
    static let live = Self(
        loadPage: { request in
            try await MerianNetworkClient.shared.getCommunityIdentificationFeed(
                limit: request.limit,
                scope: request.filter.scope,
                group: request.filter.group,
                latitude: request.latitude,
                longitude: request.longitude,
                cursor: request.cursor
            )
        },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension IdentifyActivityFeedViewModel.Dependencies {
    static let live = Self(
        loadPage: { request in
            try await MerianNetworkClient.shared.getCommunityIdentificationActivity(
                limit: request.limit,
                scope: request.filter.scope,
                group: request.filter.group,
                cursor: request.cursor
            )
        },
        errorMessage: { ExploreErrorFormatter.recentActivityMessage(for: $0) }
    )
}

extension CommunityIdentificationDetailViewModel.Dependencies {
    static let live = Self(
        loadDetail: {
            try await MerianNetworkClient.shared.getCommunityIdentificationDetail(requestId: $0)
        },
        updateRequest: { request in
            _ = try await MerianNetworkClient.shared.updateCommunityIdentificationRequest(
                requestId: request.requestId,
                note: request.note,
                locationSharing: request.locationSharing
            )
        },
        reportPost: { request in
            try await MerianNetworkClient.shared.reportExplorePost(
                postId: request.postId,
                reason: "Inappropriate content",
                details: "Reported from Community request"
            )
        },
        submitIdentification: { request in
            _ = try await MerianNetworkClient.shared.submitCommunityIdentification(
                requestId: request.requestId,
                taxonId: request.taxonId,
                disagreementMode: request.disagreementMode,
                reasoning: request.reasoning,
                isGenusBestPossible: request.isGenusBestPossible
            )
        },
        withdrawIdentification: {
            _ = try await MerianNetworkClient.shared.withdrawCommunityIdentification(
                identificationId: $0
            )
        },
        restoreIdentification: {
            _ = try await MerianNetworkClient.shared.restoreCommunityIdentification(
                identificationId: $0
            )
        },
        currentUserId: { SupabaseManager.shared.currentUser?.id.uuidString },
        requestDidChange: {
            AppDIContainer.shared.appEventPublisher.send(
                .communityIdentificationRequestChanged(requestId: $0)
            )
        },
        successFeedback: { HapticManager.shared.triggerSuccessPulse() },
        selectionFeedback: { HapticManager.shared.triggerSelectionPulse() },
        errorFeedback: { HapticManager.shared.triggerErrorThump() },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension CommunityTaxonomySearchViewModel.Dependencies {
    static let live = Self(
        debounce: { try await Task.sleep(nanoseconds: 250_000_000) },
        search: { query, taxonomyVersionId in
            try await MerianNetworkClient.shared.searchCommunityTaxa(
                query: query,
                taxonomyVersionId: taxonomyVersionId
            )
        },
        isCancellation: { ExploreErrorFormatter.isCancellation($0) },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}

extension CommunityFeedbackViewModel.Dependencies {
    static let live = Self(
        submit: { try await MerianNetworkClient.shared.submitCommunityFeedback(feedback: $0) },
        successFeedback: { HapticManager.shared.triggerSuccessPulse() },
        errorFeedback: { HapticManager.shared.triggerErrorThump() },
        errorMessage: { ExploreErrorFormatter.message(for: $0) }
    )
}
