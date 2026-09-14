import Foundation

/// Owns process-local presentation identity without owning observable UI state.
///
/// `InferenceEngine` remains the stable presentation facade, while
/// `InferenceSessionLifecycleCoordinator` sequences observable publication
/// around this owner's decisions. This coordinator only decides whether an
/// exact prepared or active presentation may transition and retains the
/// ephemeral visual handoff and first-render context associated with that
/// owner.
@MainActor
final class InferencePresentationCoordinator {
    enum Modality: Sendable {
        case visual
        case nonVisual
    }

    enum QueueSource: Sendable {
        case prepared(attemptGeneration: UUID)
        case active(attemptGeneration: UUID)
    }

    struct QueueHandoff: Equatable, Sendable {
        let scanId: String
        let scanningPhrases: [String]
        let carriesLiveMedia: Bool
    }

    private struct Owner: Sendable {
        let scanId: String?
        let attemptGeneration: UUID
        let modality: Modality

        func matches(scanId: String, attemptGeneration: UUID) -> Bool {
            self.attemptGeneration == attemptGeneration &&
                self.scanId?.caseInsensitiveCompare(scanId) == .orderedSame
        }
    }

    private struct FirstRenderMetric: Sendable {
        let scanId: String
        let startedAt: CFAbsoluteTime
    }

    private var preparedOwner: Owner?
    private var activeOwner: Owner?
    private var queuedVisualScanId: String?
    private var queuedPresentationCarriesLiveMedia = false
    private var queuedScanningPhrases: [String] = []
    private var firstRenderMetric: FirstRenderMetric?

    func prepare(
        scanId: String?,
        attemptGeneration: UUID?,
        modality: Modality
    ) {
        reset()
        guard let scanId, let attemptGeneration else { return }
        preparedOwner = Owner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: modality
        )
    }

    func activate(
        scanId: String?,
        attemptGeneration: UUID,
        modality: Modality
    ) {
        preparedOwner = nil
        activeOwner = Owner(
            scanId: scanId,
            attemptGeneration: attemptGeneration,
            modality: modality
        )
    }

    func finishActivePresentation(attemptGeneration: UUID) {
        guard activeOwner?.attemptGeneration == attemptGeneration else {
            return
        }
        activeOwner = nil
    }

    func reset() {
        clearOwnersAndQueuedVisualContext()
        firstRenderMetric = nil
    }

    func clearForPublishedResult() {
        clearOwnersAndQueuedVisualContext()
    }

    func clearForAuthTransitionAdmission() {
        clearOwnersAndQueuedVisualContext()
    }

    /// Mirrors the existing post-drain cleanup while also discarding any
    /// presentation context installed re-entrantly during the drain. The
    /// pending render metric remains available to an already-mounted probe.
    func finishAuthTransitionQuiescence() {
        clearOwnersAndQueuedVisualContext()
    }

    func transitionToQueue(
        scanId: String,
        source: QueueSource,
        isActiveAttemptCurrent: (_ scanId: String, _ attemptGeneration: UUID) -> Bool,
        activeMediaItemCount: Int,
        activeVisualPhrases: [String],
        preparedVisualPhrases: [String]
    ) -> QueueHandoff? {
        let normalizedScanId = scanId
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedScanId.isEmpty else {
            clearQueuedVisualContext()
            return nil
        }

        let owner: Owner
        let isPreparedHandoff: Bool
        switch source {
        case .prepared(let attemptGeneration):
            guard let preparedOwner,
                  preparedOwner.matches(
                      scanId: normalizedScanId,
                      attemptGeneration: attemptGeneration
                  ) else {
                clearQueuedVisualContext()
                return nil
            }
            owner = preparedOwner
            isPreparedHandoff = true
        case .active(let attemptGeneration):
            guard let activeOwner,
                  activeOwner.matches(
                      scanId: normalizedScanId,
                      attemptGeneration: attemptGeneration
                  ),
                  isActiveAttemptCurrent(
                      normalizedScanId,
                      attemptGeneration
                  ) else {
                clearQueuedVisualContext()
                return nil
            }
            owner = activeOwner
            isPreparedHandoff = false
        }

        clearQueuedVisualContext()
        var phrases: [String] = []
        var carriesLiveMedia = false
        if case .visual = owner.modality {
            queuedVisualScanId = normalizedScanId
            carriesLiveMedia = !isPreparedHandoff && activeMediaItemCount > 0
            queuedPresentationCarriesLiveMedia = carriesLiveMedia
            phrases = isPreparedHandoff
                ? preparedVisualPhrases
                : activeVisualPhrases
            queuedScanningPhrases = phrases
        }

        preparedOwner = nil
        activeOwner = nil
        firstRenderMetric = nil
        return QueueHandoff(
            scanId: normalizedScanId,
            scanningPhrases: phrases,
            carriesLiveMedia: carriesLiveMedia
        )
    }

    func scanningPhrases(for scanId: String) -> [String] {
        guard queuedVisualScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame else {
            return []
        }
        return queuedScanningPhrases
    }

    func hasVisualQueueHandoff(for scanId: String) -> Bool {
        queuedVisualScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame
    }

    func hasLiveMedia(for scanId: String) -> Bool {
        queuedPresentationCarriesLiveMedia &&
            hasVisualQueueHandoff(for: scanId)
    }

    func isActiveVisual(attemptGeneration: UUID?) -> Bool {
        guard let attemptGeneration,
              activeOwner?.attemptGeneration == attemptGeneration,
              case .visual = activeOwner?.modality else {
            return false
        }
        return true
    }

    func beginFirstRenderMetric(
        scanId: String,
        startedAt: CFAbsoluteTime
    ) {
        firstRenderMetric = FirstRenderMetric(
            scanId: scanId,
            startedAt: startedAt
        )
    }

    /// Transfers a pending clock from a queue-less request's process-local ID
    /// to the authoritative ID assigned by the server response. Exact source
    /// matching prevents a stale completion from adopting another attempt's
    /// metric.
    func rebindFirstRenderMetric(
        from sourceScanId: String,
        to resultScanId: String
    ) {
        guard let firstRenderMetric,
              firstRenderMetric.scanId.caseInsensitiveCompare(sourceScanId)
                == .orderedSame else {
            return
        }
        self.firstRenderMetric = FirstRenderMetric(
            scanId: resultScanId,
            startedAt: firstRenderMetric.startedAt
        )
    }

    func consumeFirstRenderStart(scanId: String) -> CFAbsoluteTime? {
        guard let firstRenderMetric,
              firstRenderMetric.scanId
                .caseInsensitiveCompare(scanId) == .orderedSame else {
            return nil
        }
        self.firstRenderMetric = nil
        return firstRenderMetric.startedAt
    }

    private func clearOwnersAndQueuedVisualContext() {
        preparedOwner = nil
        activeOwner = nil
        clearQueuedVisualContext()
    }

    private func clearQueuedVisualContext() {
        queuedVisualScanId = nil
        queuedPresentationCarriesLiveMedia = false
        queuedScanningPhrases = []
    }
}
