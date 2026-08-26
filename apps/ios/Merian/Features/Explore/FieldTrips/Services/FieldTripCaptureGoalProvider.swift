import Foundation

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
                if let imageName = FieldTripGoalArtwork.exactImageName(
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
              template.viewerProgress == nil,
              let firstLevel = template.levels.min(by: { $0.levelNumber < $1.levelNumber }),
              !firstLevel.items.isEmpty else {
            return nil
        }

        let goalCount = firstLevel.items.count
        let goalLabel = goalCount == 1 ? "goal" : "goals"
        let title = FieldTripTemplatePresentation.title(template.title, slug: template.slug)
        let artworks = firstLevel.items.map { item -> CaptureGoalArtwork in
            if let imageName = FieldTripGoalArtwork.exactImageName(
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
