import Foundation
import Observation

struct FieldTripCaptureGoalProvider: CaptureGoalContextProviding {
    typealias FetchContext = @Sendable () async throws -> [FieldTripCaptureOuting]
    typealias FetchTemplate = @Sendable (_ slug: String) async throws -> FieldTripTemplate

    init(
        fetchContext: @escaping FetchContext = {
            try await MerianNetworkClient.shared.getFieldTripCaptureContext()
        },
        fetchTemplate: @escaping FetchTemplate = { slug in
            try await MerianNetworkClient.shared.getFieldTripTemplate(slug: slug)
        }
    ) {
        self.fetchContext = fetchContext
        self.fetchTemplate = fetchTemplate
    }

    private let fetchContext: FetchContext
    private let fetchTemplate: FetchTemplate

    func fetchCaptureGoalContext() async throws -> CaptureGoalContextSnapshot {
        let outings = try await fetchContext()
        let goals = outings.flatMap { outing in
            outing.targets.map { target in
                let artwork: CaptureGoalArtwork
                if let imageName = FieldTripObjectiveArtwork.exactImageName(
                    for: target.prompt,
                    templateSlug: outing.templateSlug
                ) {
                    artwork = .bundledImage(name: imageName)
                } else {
                    artwork = .systemSymbol(name: "binoculars.fill")
                }

                return CaptureGoal(
                    id: "field_trip:\(target.itemId)",
                    source: CaptureGoalSource(
                        kind: .fieldTrip,
                        id: outing.userFieldTripId,
                        title: outing.outingTitle
                    ),
                    prompt: target.prompt,
                    progress: CaptureGoalProgress(
                        completedCount: outing.completedCount,
                        targetCount: outing.targetCount
                    ),
                    artwork: artwork,
                    destination: .fieldTrip(
                        templateId: outing.templateId,
                        checklistItemId: target.itemId
                    )
                )
            }
        }

        guard goals.isEmpty else {
            return CaptureGoalContextSnapshot(goals: goals, introduction: nil)
        }

        let template = try await fetchTemplate(FieldTripTemplatePresentation.backyardSafariSlug)
        return CaptureGoalContextSnapshot(
            goals: [],
            introduction: makeIntroduction(from: template)
        )
    }

    private func makeIntroduction(from template: FieldTripTemplate) -> CaptureGoalIntroduction? {
        guard template.slug == FieldTripTemplatePresentation.backyardSafariSlug,
              template.viewerHasAccess,
              template.activeProgress == nil,
              let firstLevel = template.levels.min(by: { $0.levelNumber < $1.levelNumber }),
              !firstLevel.items.isEmpty else {
            return nil
        }

        let goalCount = firstLevel.items.count
        let goalLabel = goalCount == 1 ? "goal" : "goals"
        let title = FieldTripTemplatePresentation.title(template.title, slug: template.slug)
        let artworks = firstLevel.items.map { item -> CaptureGoalArtwork in
            if let imageName = FieldTripObjectiveArtwork.exactImageName(
                for: item.prompt,
                templateSlug: template.slug
            ) {
                return .bundledImage(name: imageName)
            }
            return .systemSymbol(name: "binoculars.fill")
        }

        return CaptureGoalIntroduction(
            id: "field_trip_introduction:\(template.slug)",
            sourceKind: .fieldTrip,
            headline: "Start an outing",
            subheadline: "\(title) · \(goalCount) \(goalLabel)",
            progress: CaptureGoalProgress(completedCount: 0, targetCount: goalCount),
            artworks: artworks,
            destination: .fieldTripTemplate(slug: template.slug),
            accessibilityLabel: "Start an outing. \(title), \(goalCount) \(goalLabel).",
            accessibilityValue: "0 of \(goalCount) \(goalLabel) complete.",
            accessibilityHint: "Opens outing details."
        )
    }
}

@MainActor
@Observable
final class FieldTripsViewModel {
    var templates: [FieldTripTemplate] = []
    var challenges: [FieldTripChallenge] = []
    var isLoading = false
    var errorMessage: String?
    var challengeErrorMessage: String?
    var toastMessage: String?

    private var didLoad = false

    func load(userRegion: String? = nil, force: Bool = false) async {
        guard force || !didLoad else { return }
        isLoading = true
        errorMessage = nil
        challengeErrorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }

        do {
            templates = try await MerianNetworkClient.shared.getFieldTrips(userRegion: userRegion)
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }

        do {
            challenges = try await MerianNetworkClient.shared.getFieldTripChallenges(userRegion: userRegion)
        } catch {
            challengeErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func refresh(userRegion: String? = nil) async {
        await load(userRegion: userRegion, force: true)
    }

    func template(withId templateId: String) -> FieldTripTemplate? {
        templates.first { $0.templateId == templateId }
    }

    func replaceTemplate(_ template: FieldTripTemplate) {
        guard let index = templates.firstIndex(where: { $0.templateId == template.templateId }) else {
            return
        }
        templates[index] = template
    }

    func challenge(withId challengeId: String) -> FieldTripChallenge? {
        challenges.first { $0.challengeId == challengeId }
    }

    func replaceChallenge(_ challenge: FieldTripChallenge) {
        guard let index = challenges.firstIndex(where: { $0.challengeId == challenge.challengeId }) else {
            return
        }
        challenges[index] = challenge
    }

}

@MainActor
@Observable
final class FieldTripChallengeDetailViewModel {
    var challenge: FieldTripChallenge?
    var entries: [FieldTripChallengeEntry] = []
    var isLoading = false
    var isJoining = false
    var isLoadingMoreEntries = false
    var errorMessage: String?
    var toastMessage: String?
    var hasMoreEntries = true

    private let challengeId: String
    private let entriesPageSize = 12

    init(challengeId: String) {
        self.challengeId = challengeId
    }

    func load(force: Bool = false) async {
        guard force || challenge == nil else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let loaded = try await MerianNetworkClient.shared.getFieldTripChallenge(
                challengeId: challengeId,
                entriesLimit: entriesPageSize
            )
            challenge = loaded
            entries = loaded.entries
            hasMoreEntries = loaded.entries.count >= entriesPageSize
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func refresh() async {
        await load(force: true)
    }

    func join() async {
        guard !isJoining else { return }
        isJoining = true
        errorMessage = nil
        defer { isJoining = false }

        do {
            let loaded = try await MerianNetworkClient.shared.joinFieldTripChallenge(challengeId: challengeId)
            challenge = loaded
            entries = loaded.entries
            hasMoreEntries = loaded.entries.count >= entriesPageSize
            HapticManager.shared.triggerSuccessPulse()
            toastMessage = "Challenge joined."
            AppEventPublisher.shared.send(.captureGoalContextInvalidated(source: .fieldTrip))
        } catch {
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func loadMoreEntries() async {
        guard hasMoreEntries,
              !isLoadingMoreEntries,
              let cursor = entries.last else {
            return
        }

        isLoadingMoreEntries = true
        defer { isLoadingMoreEntries = false }

        do {
            let page = try await MerianNetworkClient.shared.getFieldTripChallengePublications(
                challengeId: challengeId,
                limit: entriesPageSize,
                beforePublishedAt: cursor.publishedAt,
                beforeEntryId: cursor.entryId
            )
            entries.append(contentsOf: page)
            hasMoreEntries = page.count >= entriesPageSize
        } catch {
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }
}

@MainActor
@Observable
final class FieldTripPublicationViewModel {
    var detail: FieldTripPublicationDetail?
    var comments: [ExploreComment] = []
    var commentDraft = ""
    var isLoading = false
    var isLoadingComments = false
    var isSubmittingComment = false
    var isUpdatingLike = false
    var errorMessage: String?
    var commentErrorMessage: String?
    var toastMessage: String?

    private let publicationId: String

    init(publicationId: String) {
        self.publicationId = publicationId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await MerianNetworkClient.shared.getFieldTripPublication(publicationId: publicationId)
            await loadComments()
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func loadComments() async {
        isLoadingComments = true
        commentErrorMessage = nil
        defer { isLoadingComments = false }

        do {
            comments = try await MerianNetworkClient.shared.getFieldTripComments(publicationId: publicationId)
        } catch {
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func toggleLike() async {
        guard var current = detail, !isUpdatingLike else { return }
        isUpdatingLike = true
        defer { isUpdatingLike = false }

        let targetLiked = !current.viewerHasLiked
        current.viewerHasLiked = targetLiked
        current.likeCount = max(0, current.likeCount + (targetLiked ? 1 : -1))
        detail = current

        do {
            let response = try await MerianNetworkClient.shared.setFieldTripLike(
                publicationId: publicationId,
                liked: targetLiked
            )
            current.viewerHasLiked = response.viewerHasLiked
            current.likeCount = response.likeCount
            if let commentCount = response.commentCount {
                current.commentCount = commentCount
            }
            detail = current
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            current.viewerHasLiked.toggle()
            current.likeCount = max(0, current.likeCount + (targetLiked ? -1 : 1))
            detail = current
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func submitComment() async {
        guard var current = detail, !isSubmittingComment else { return }
        let trimmed = String(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return }

        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""
        defer { isSubmittingComment = false }

        do {
            let response = try await MerianNetworkClient.shared.createFieldTripComment(
                publicationId: publicationId,
                body: trimmed
            )
            comments.append(response.comment)
            current.commentCount = response.commentCount
            detail = current
            HapticManager.shared.triggerSuccessPulse()
        } catch {
            commentDraft = previousDraft
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }
}

@MainActor
@Observable
final class FieldTripChallengeEntryViewModel {
    var detail: FieldTripChallengeEntryDetail?
    var comments: [ExploreComment] = []
    var commentDraft = ""
    var isLoading = false
    var isLoadingComments = false
    var isSubmittingComment = false
    var isUpdatingLike = false
    var errorMessage: String?
    var commentErrorMessage: String?
    var toastMessage: String?

    private let entryId: String

    init(entryId: String) {
        self.entryId = entryId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await MerianNetworkClient.shared.getFieldTripChallengeEntry(entryId: entryId)
            await loadComments()
        } catch {
            errorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func loadComments() async {
        isLoadingComments = true
        commentErrorMessage = nil
        defer { isLoadingComments = false }

        do {
            comments = try await MerianNetworkClient.shared.getFieldTripChallengeEntryComments(entryId: entryId)
        } catch {
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func toggleLike() async {
        guard var current = detail, !isUpdatingLike else { return }
        isUpdatingLike = true
        defer { isUpdatingLike = false }

        let targetLiked = !current.viewerHasLiked
        current.viewerHasLiked = targetLiked
        current.likeCount = max(0, current.likeCount + (targetLiked ? 1 : -1))
        detail = current

        do {
            let response = try await MerianNetworkClient.shared.setFieldTripChallengeEntryLike(
                entryId: entryId,
                liked: targetLiked
            )
            current.viewerHasLiked = response.viewerHasLiked
            current.likeCount = response.likeCount
            if let commentCount = response.commentCount {
                current.commentCount = commentCount
            }
            detail = current
            HapticManager.shared.triggerSelectionPulse()
        } catch {
            current.viewerHasLiked.toggle()
            current.likeCount = max(0, current.likeCount + (targetLiked ? -1 : 1))
            detail = current
            HapticManager.shared.triggerErrorThump()
            toastMessage = ExploreErrorFormatter.message(for: error)
        }
    }

    func submitComment() async {
        guard var current = detail, !isSubmittingComment else { return }
        let trimmed = String(commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { return }

        isSubmittingComment = true
        commentErrorMessage = nil
        let previousDraft = commentDraft
        commentDraft = ""
        defer { isSubmittingComment = false }

        do {
            let response = try await MerianNetworkClient.shared.createFieldTripChallengeEntryComment(
                entryId: entryId,
                body: trimmed
            )
            comments.append(response.comment)
            current.commentCount = response.commentCount
            detail = current
            HapticManager.shared.triggerSuccessPulse()
        } catch {
            commentDraft = previousDraft
            commentErrorMessage = ExploreErrorFormatter.message(for: error)
            HapticManager.shared.triggerErrorThump()
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
