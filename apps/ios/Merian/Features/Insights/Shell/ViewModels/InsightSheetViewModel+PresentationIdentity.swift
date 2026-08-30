import Foundation

extension InsightSheetViewModel {
    var currentFieldNotesScanId: String? {
        if let ctx = queuedContext { return ctx.id }
        if inferenceEngine?.speciesData?.scanId != nil {
            return presentedLocalRecordScanId
        }
        return inferenceEngine?.activeScanId
    }

    /// The completed engine result is the presentation authority. Any cached
    /// record identity must agree before a scan-bound action may combine the
    /// two sources.
    var presentedSpeciesScanId: String? {
        guard queuedContext == nil,
              let rawScanId = inferenceEngine?.speciesData?.scanId else {
            return nil
        }

        let scanId = rawScanId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scanId.isEmpty else { return nil }

        let cachedScanIds = [
            activeLocalRecord?.id,
            activeLocalRecordId,
            toolbarRecordSnapshot?.scanId
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard cachedScanIds.allSatisfy({
            $0.caseInsensitiveCompare(scanId) == .orderedSame
        }) else {
            return nil
        }

        return scanId
    }

    /// Exact persisted-record identity for actions that mutate local state or
    /// reuse scan-bound server state. Unlike Field Chat presentation, these
    /// actions cannot proceed before the local record and snapshot are bound.
    var presentedLocalRecordScanId: String? {
        guard let scanId = presentedSpeciesScanId,
              let activeLocalRecord,
              activeLocalRecord.id.caseInsensitiveCompare(scanId) == .orderedSame,
              let activeLocalRecordId,
              activeLocalRecordId.caseInsensitiveCompare(scanId) == .orderedSame,
              let snapshot = toolbarRecordSnapshot,
              snapshot.scanId.caseInsensitiveCompare(scanId) == .orderedSame else {
            return nil
        }
        return scanId
    }

    func isPresentingLocalRecord(
        scanId: String,
        generation: UInt64? = nil
    ) -> Bool {
        if let generation, generation != scanBoundActionGeneration {
            return false
        }
        return presentedLocalRecordScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame
    }

    /// Exact identity for controls that are also available while a scan is
    /// still queued. The generation rejects an obsolete A presentation even
    /// when the same scan ID later appears again after an A → B → A switch.
    func isPresentingScan(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        guard generation == scanBoundActionGeneration else { return false }
        if let queuedContext {
            return queuedContext.id.caseInsensitiveCompare(scanId) == .orderedSame
        }
        return isPresentingLocalRecord(scanId: scanId, generation: generation)
    }

    /// Exact identity for read-only media callbacks, which remain available
    /// before a completed local record has been bound. This deliberately uses
    /// the presentation authority rather than the destructive-action helper.
    func isPresentingMedia(
        scanId: String,
        generation: UInt64
    ) -> Bool {
        guard generation == scanBoundActionGeneration else { return false }
        return persistentScanId?
            .caseInsensitiveCompare(scanId) == .orderedSame
    }

    /// Reveals result-only actions after their presentation has settled.
    /// A completed record may reuse the queued row's scan ID, so callers must
    /// provide the monotonic presentation generation as the identity fence.
    @discardableResult
    func revealBottomBarTools(
        expectedScanId scanId: String,
        expectedGeneration generation: UInt64
    ) -> Bool {
        guard queuedContext == nil,
              isPresentingLocalRecord(
                  scanId: scanId,
                  generation: generation
              ),
              toolbarRecordSnapshot?.scanId
                .caseInsensitiveCompare(scanId) == .orderedSame else {
            return false
        }
        state.showBottomBarTools = true
        return true
    }

    var fieldNotesText: String {
        if queuedContext == nil,
           inferenceEngine?.speciesData?.scanId != nil,
           presentedLocalRecordScanId == nil {
            return ""
        }
        return state.fieldNotesText
    }

    var hasFieldNotes: Bool {
        !fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldShowFieldNotesCard: Bool {
        guard !hasFieldNotes else { return true }
        guard let currentFieldNotesScanId else { return true }
        return state.dismissedFieldNotesCardScanId != currentFieldNotesScanId
    }

    var shareableFieldNotes: String? {
        let trimmed = fieldNotesText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var fieldNotesPromptContext: FieldNotesPromptContext {
        FieldNotesPromptResolver.context(for: inferenceEngine?.speciesData)
    }

}
