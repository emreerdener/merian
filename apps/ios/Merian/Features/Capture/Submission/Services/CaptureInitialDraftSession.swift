import Foundation
import Observation

/// Observation identity is independent of presentation generations and item
/// order. Every source handle is retained before storage can save anything;
/// uncertain writes keep that handle for exact retry or explicit discard.
@Observable @MainActor
final class CaptureInitialDraftSession {
    struct Identity: Equatable, Sendable {
        let ownerID: UUID
        let scanID: UUID
        let generation: UUID
    }
    struct Source: Equatable, Sendable {
        let itemID: UUID
        let input: SharedMediaCaptureDraftSourceInput
        var ready: Bool
    }
    enum Review: Equatable, Sendable {
        case photo(SharedMediaNativePreparationRecipe)
        case video(SharedMediaCaptureDraftJournal.VideoRecipe)
    }
    let identity: Identity
    private(set) var sources: [Source] = []
    private(set) var isBusy = false
    private(set) var frozenPlan: CaptureInitialEvidencePlan?
    private var prepared: CaptureInitialEvidencePreparation.Prepared?
    private var preparedItems: [CaptureInitialEvidencePreparation.Item]?
    private var frozenContext: SharedMediaCaptureSubmissionContext?
    var submissionContext: SharedMediaCaptureSubmissionContext? { frozenContext }
    private(set) var journal: SharedMediaCaptureDraftJournalReceipt.Snapshot?
    private var journalSources: [SharedMediaCaptureDraftJournal.Source] = []
    private var reviewItems: [SharedMediaCaptureDraftJournal.Item] = []
    private var owner: SharedMediaNativeOriginalOwner?
    private var abortRecovery: SharedMediaCaptureAbortRecovery.Handle?
    private var nextOrdinal = 0
    private let hasher = CaptureInitialSourceHasher()
    private let resolveOwner: () async throws -> SharedMediaNativeOriginalOwner
    private let requireCurrent: () throws -> Void
    var needsPreparationAbort: Bool { abortRecovery != nil || journal?.value.phase == .abortingPreparation }

    init(identity: Identity, requireCurrent: @escaping () throws -> Void,
         resolveOwner: @escaping () async throws -> SharedMediaNativeOriginalOwner) {
        self.identity = identity; self.requireCurrent = requireCurrent; self.resolveOwner = resolveOwner
    }

    static func app(ownerID: UUID, diContainer: AppDIContainer) async throws -> CaptureInitialDraftSession {
        let container = diContainer.offlineQueueManager.modelContext?.container
        let authGeneration = diContainer.supabaseManager.authSessionGeneration
        let requireCurrent = {
            guard let container, diContainer.offlineQueueManager.modelContext?.container === container,
                  diContainer.supabaseManager.authSessionGeneration == authGeneration,
                  diContainer.supabaseManager.currentUser?.id == ownerID,
                  !diContainer.supabaseManager.isAuthTransitionInProgress,
                  !diContainer.supabaseManager.libraryAccountRecoveryRequired,
                  !diContainer.supabaseManager.librarySignOutRecoveryPending else { throw SharedMediaStorageFailure.closed }
        }
        let resolveOwner = {
            try requireCurrent()
            let owner = try await diContainer.nativeMediaLifecycle.nativeMediaOwnerForCaptureDraft()
            try requireCurrent()
            return owner
        }
        let owner = try await resolveOwner()
        var cursor: String?, retained: SharedMediaCaptureDraftJournalReceipt.Snapshot?
        // Multiple unfinished editors require explicit selection; never create
        // a fresh draft to hide an ambiguous or unenumerated saved composition.
        for _ in 0..<64 {
            let page: SharedMediaCaptureDraftJournalRecovery.Page
            do { page = try await owner.captureDraftJournalPage(after: cursor) } catch SharedMediaStorageFailure.closed {
                let handles = try await owner.capturePreparationAbortRecovery()
                try requireCurrent(); try Task.checkCancellation()
                guard handles.count == 1, let handle = handles.first else { throw SharedMediaStorageFailure.closed }
                return abortOnly(handle, owner: owner, ownerID: ownerID, requireCurrent: requireCurrent, resolveOwner: resolveOwner)
            }
            try requireCurrent(); try Task.checkCancellation()
            for saved in page.drafts where saved.value.phase != .accepted {
                guard retained == nil else { throw SharedMediaStorageFailure.closed }
                retained = saved
            }
            guard let next = page.nextCursor else {
                if let retained {
                    return try await reopen(retained, requireCurrent: requireCurrent, resolveOwner: resolveOwner)
                }
                return .init(identity: .init(ownerID: ownerID, scanID: UUID(), generation: UUID()),
                    requireCurrent: requireCurrent, resolveOwner: resolveOwner)
            }
            guard next != cursor else { throw SharedMediaStorageFailure.conflict }
            cursor = next
        }
        throw SharedMediaStorageFailure.capacity
    }

    /// The discovered receipt is descriptive. Revalidate it through the current
    /// root owner before restoring any review or execution identity.
    static func reopen(_ expected: SharedMediaCaptureDraftJournalReceipt.Snapshot,
                       requireCurrent: @escaping () throws -> Void,
                       resolveOwner: @escaping () async throws -> SharedMediaNativeOriginalOwner) async throws -> CaptureInitialDraftSession {
        try requireCurrent(); try Task.checkCancellation()
        let owner = try await resolveOwner()
        var value = expected.value
        let current: SharedMediaCaptureDraftJournalReceipt.Snapshot?
        do {
            current = try await owner.readAppCaptureDraftJournal(scanID: value.scanID, generation: value.generation)
        } catch SharedMediaStorageFailure.closed {
            let handles = try await owner.capturePreparationAbortRecovery()
            try requireCurrent(); try Task.checkCancellation()
            guard handles.count == 1, let handle = handles.first,
                  SharedMediaCaptureAbortRecovery.expected(handle) == expected else { throw SharedMediaStorageFailure.stale }
            return abortOnly(handle, owner: owner, ownerID: value.profile.ownerID, requireCurrent: requireCurrent, resolveOwner: resolveOwner)
        }
        try requireCurrent(); try Task.checkCancellation()
        guard current == expected, value.phase != .released else { throw SharedMediaStorageFailure.stale }
        let recovered: SharedMediaCaptureDraftJournalReceipt.Snapshot
        if value.phase == .editing {
            recovered = try await owner.recoverReadyAppCaptureDraft(expected)
            try requireCurrent(); try Task.checkCancellation()
            value = recovered.value
        } else { recovered = expected }
        let session = CaptureInitialDraftSession(identity: .init(ownerID: value.profile.ownerID,
            scanID: value.scanID, generation: value.generation), requireCurrent: requireCurrent, resolveOwner: resolveOwner)
        session.owner = owner; session.journal = recovered
        session.journalSources = value.sources; session.reviewItems = value.items
        session.sources = value.sources.filter { !$0.state.isTerminal }.map {
            .init(itemID: $0.itemID, input: $0.input, ready: $0.state == .ready)
        }
        session.nextOrdinal = (value.sources.map { $0.input.itemIndex }.max() ?? -1) + 1
        if value.phase != .abortingPreparation, let frozen = value.frozenObservation ?? value.preparation?.observation {
            let plan = try CaptureInitialEvidencePlan(ownerID: value.profile.ownerID, data: frozen.bytes)
            session.frozenPlan = plan; session.frozenContext = value.frozenContext
            // Acceptance can replay already durable members. A missing frozen
            // derivative stays held; reopening cannot remint IDs or pixels.
            session.prepared = .init(plan: plan, derivatives: [:])
        }
        return session
    }

    struct Retention {
        let itemID: UUID
        let bytes: Data
        let role: SharedMediaCaptureArtifactRequest.Role
        let contentType: String
        let context: SharedMediaCaptureDraftSourceContext
        let review: Review?
    }

    /// The caller's item key precedes loading/preparation and survives retry.
    /// A changed original cannot replace an uncertain saved source at that key.
    func retain(itemID: UUID, bytes: Data, role: SharedMediaCaptureArtifactRequest.Role,
                contentType: String, context: SharedMediaCaptureDraftSourceContext,
                review: Review? = nil) async throws -> SharedMediaCaptureDraftSourceInput {
        let inputs = try await retainSources([.init(itemID: itemID, bytes: bytes, role: role,
            contentType: contentType, context: context, review: review)])
        guard let input = inputs.first else { throw SharedMediaStorageFailure.conflict }
        return input
    }

    /// A video's physical original and its companion are declared together
    /// before either write. Interruption cannot turn an incomplete pair into a
    /// ready silent video. Retrying preserves every allocated source identity.
    func retainSources(_ requests: [Retention]) async throws -> [SharedMediaCaptureDraftSourceInput] {
        try requireEditable()
        guard !requests.isEmpty, requests.count <= 64 else { throw SharedMediaStorageFailure.capacity }
        isBusy = true; defer { isBusy = false }
        var digests: [String] = []
        for request in requests {
            try request.role.require(contentType: request.contentType, byteCount: Int64(request.bytes.count), frameIndex: nil)
            try request.context.validate(role: request.role)
            digests.append(try await hasher.digest(request.bytes))
            try requireCurrent(); try Task.checkCancellation()
        }
        let previousSources = sources, previousJournalSources = journalSources
        let previousItems = reviewItems, previousOrdinal = nextOrdinal
        var indices: [Int] = []
        do {
            for (request, digest) in zip(requests, digests) {
                switch (request.role, request.review) {
                case let (.sourceImage, .photo(recipe)): try recipe.validate()
                case let (.sourceVideo, .video(recipe)): try recipe.validate()
                case (.sourceAudio, nil), (.sourceCompanionAudio, nil): break
                default: throw SharedMediaStorageFailure.invalid
                }
                let index: Int
                if let existing = sources.firstIndex(where: { $0.itemID == request.itemID && $0.input.role == request.role }) {
                    let input = sources[existing].input
                    guard input.byteCount == request.bytes.count, input.sha256 == digest,
                          input.contentType == request.contentType, input.context == request.context else {
                        throw SharedMediaStorageFailure.conflict
                    }
                    index = existing
                } else {
                    guard nextOrdinal < 64 else { throw SharedMediaStorageFailure.capacity }
                    let ordinal = sources.first(where: { $0.itemID == request.itemID })?.input.itemIndex ?? nextOrdinal
                    let input = SharedMediaCaptureDraftSourceInput(id: UUID(), scanID: identity.scanID,
                        submissionGeneration: identity.generation, mediaID: UUID(), itemIndex: ordinal,
                        role: request.role, contentType: request.contentType, byteCount: Int64(request.bytes.count),
                        sha256: digest, context: request.context)
                    sources.append(.init(itemID: request.itemID, input: input, ready: false))
                    journalSources.append(.init(itemID: request.itemID, input: input, state: .pending))
                    if ordinal == nextOrdinal { nextOrdinal += 1 }
                    index = sources.count - 1
                }
                guard !indices.contains(index) else { throw SharedMediaStorageFailure.conflict }
                indices.append(index)
                try retainReviewItem(itemID: request.itemID, input: sources[index].input, review: request.review)
            }
            if let value = journal?.value {
                try SharedMediaCaptureDraftJournal(format: value.format, profile: value.profile,
                    rootBindingSHA256: value.rootBindingSHA256, scanID: value.scanID, generation: value.generation,
                    revision: value.revision + 1, phase: .editing, sources: journalSources, items: reviewItems,
                    frozenObservation: nil, frozenContext: nil, abortedPreparations: value.abortedPreparations).validate()
            }
        } catch {
            // No I/O has occurred. Invalid membership cannot poison the editor.
            sources = previousSources; journalSources = previousJournalSources
            reviewItems = previousItems; nextOrdinal = previousOrdinal
            throw error
        }
        let owner = try await admittedOwner()
        try requireCurrent(); try Task.checkCancellation()
        try await saveJournal(owner)
        for (request, index) in zip(requests, indices) {
            let input = sources[index].input
            let saved = try await owner.materializeAppCaptureSource(input, bytes: request.bytes)
            guard saved.request.profile.ownerID == identity.ownerID,
                  try SharedMediaCaptureDraftSourceInput(retained: saved.request) == input,
                  saved.phase == .ready, saved.retirement == nil,
                  let member = journalSources.firstIndex(where: { $0.input == input }) else {
                throw SharedMediaStorageFailure.conflict
            }
            journalSources[member].state = .ready
            try await saveJournal(owner)
            sources[index].ready = true
            try requireCurrent(); try Task.checkCancellation()
        }
        return indices.map { sources[$0].input }
    }

    func read(_ input: SharedMediaCaptureDraftSourceInput) async throws -> Data {
        try requireCurrent()
        guard !isBusy, sources.contains(where: { $0.input == input && $0.ready }) else { throw SharedMediaStorageFailure.closed }
        isBusy = true; defer { isBusy = false }
        let owner = try await admittedOwner()
        try requireCurrent()
        let bytes = try await owner.readAppCaptureSource(input)
        try requireCurrent(); try Task.checkCancellation()
        return bytes
    }

    /// Hold the editing lock through every source read and disposable preview
    /// write. A frozen observation must replay its durable outputs instead.
    func editingPresentation(resources: CaptureDraftPresentationResources? = nil) async throws -> CaptureInitialDraftPresentation {
        try requireEditable()
        let resources = resources ?? CaptureDraftPresentationResources()
        guard let journal else { return .init(capture: StagedCapture(), resources: resources) }
        isBusy = true; defer { isBusy = false }
        let presentation = try await CaptureInitialDraftPresentation.make(journal: journal.value, resources: resources) { [self] input in
            try await readForPreparation(input)
        }
        do {
            try requireCurrent(); try Task.checkCancellation()
            return presentation
        } catch {
            await presentation.discard()
            throw error
        }
    }

    /// Frozen review produces only disposable UI artifacts. Missing evidence
    /// stays missing: no result is installed into prepared.derivatives and no
    /// journal revision or submission identity is changed by this projection.
    func reviewPresentation(resources: CaptureDraftPresentationResources) async throws -> CaptureInitialDraftPresentation {
        if frozenPlan == nil { return try await editingPresentation(resources: resources) }
        try requireCurrent(); try Task.checkCancellation()
        guard !isBusy, abortRecovery == nil, let journal, let frozenPlan,
              (journal.value.frozenObservation ?? journal.value.preparation?.observation)?.bytes == (try frozenPlan.encoded()) else {
            throw SharedMediaStorageFailure.closed
        }
        isBusy = true; defer { isBusy = false }
        let presentation = try await CaptureInitialDraftPresentation.make(journal: journal.value,
            mode: .frozenReadOnly, resources: resources) { [self] input in try await readForPreparation(input) }
        do {
            try requireCurrent(); try Task.checkCancellation()
            return presentation
        } catch {
            await presentation.discard()
            throw error
        }
    }

    /// Review is optional, but edits to selection, ordering, and notes must
    /// survive a restart before submission. This cannot add or remove media:
    /// those transitions belong to retain/discard and their original holds.
    func updateReview(items: [SharedMediaCaptureDraftJournal.Item]) async throws {
        try requireEditable()
        guard let journal else { throw SharedMediaStorageFailure.closed }
        let previousMedia = reviewItems.filter { if case .description = $0 { return false }; return true }
        let nextMedia = items.filter { if case .description = $0 { return false }; return true }
        guard Set(previousMedia.map(\.id)) == Set(nextMedia.map(\.id)) else {
            throw SharedMediaStorageFailure.conflict
        }
        // The journal validator binds each item to the exact retained source,
        // media kind, and optional companion; only its review recipe may vary.
        let next = SharedMediaCaptureDraftJournal(format: journal.value.format, profile: journal.value.profile,
            rootBindingSHA256: journal.value.rootBindingSHA256, scanID: identity.scanID,
            generation: identity.generation, revision: try SharedMediaStoragePolicy.add(journal.value.revision, 1),
            phase: .editing, sources: journalSources, items: items, frozenObservation: nil, frozenContext: nil,
            abortedPreparations: journal.value.abortedPreparations)
        try next.validate()
        isBusy = true; defer { isBusy = false }
        let owner = try await admittedOwner()
        reviewItems = items
        try await saveJournal(owner)
        try requireCurrent(); try Task.checkCancellation()
    }

    func discard(itemID: UUID) async throws {
        try requireCurrent(); try Task.checkCancellation()
        guard !isBusy, frozenPlan == nil, abortRecovery == nil,
              journal == nil || journal?.value.phase == .editing || journal?.value.phase == .discarding else {
            throw SharedMediaStorageFailure.closed
        }
        let selected = sources.filter { $0.itemID == itemID }
        guard !selected.isEmpty else { throw SharedMediaStorageFailure.conflict }
        isBusy = true; defer { isBusy = false }
        let owner = try await admittedOwner()
        // A failed first journal save may have no durable row yet. Establish
        // its exact pending identity before recording discard intent.
        if journal == nil { try await saveJournal(owner) }
        for index in journalSources.indices where journalSources[index].itemID == itemID {
            journalSources[index].state = .discarding
        }
        try await saveJournal(owner)
        guard let journal else { throw SharedMediaStorageFailure.conflict }
        let finished = try await owner.discardAppCaptureDraftItem(itemID: itemID, expected: journal)
        self.journal = finished; journalSources = finished.value.sources; reviewItems = finished.value.items
        sources.removeAll { $0.itemID == itemID }
        try requireCurrent()
    }

    /// Explicitly abandons a pre-parent preparation as a whole. A successful
    /// return keeps the original media and review edits available for another
    /// attempt; a failure keeps the durable abort held and resumable.
    func abortPreparation() async throws {
        try requireCurrent(); try Task.checkCancellation()
        guard !isBusy else { throw SharedMediaStorageFailure.closed }
        isBusy = true; defer { isBusy = false }
        let owner = try await admittedOwner()
        let result: SharedMediaCaptureDraftJournalReceipt.Snapshot
        if let abortRecovery {
            result = try await owner.abortAppCapturePreparation(abortRecovery)
        } else if let journal, journal.value.phase == .preparing || journal.value.phase == .abortingPreparation {
            if let frozenPlan {
                guard journal.value.preparation?.observation.bytes == (try frozenPlan.encoded()) else { throw SharedMediaStorageFailure.stale }
            }
            result = try await owner.abortAppCapturePreparation(journal)
        } else {
            guard let frozenPlan else { throw SharedMediaStorageFailure.closed }
            if abortRecovery == nil {
                let handles = try await owner.capturePreparationAbortRecovery()
                guard let handle = handles.first(where: { $0.scanID == identity.scanID && $0.generation == identity.generation }),
                      handle.planSHA256 == (try SharedMediaAcquisitionEncoding.digest(frozenPlan.encoded())) else {
                    throw SharedMediaStorageFailure.stale
                }
                abortRecovery = handle
            }
            guard let abortRecovery else { throw SharedMediaStorageFailure.closed }
            result = try await owner.abortAppCapturePreparation(abortRecovery)
        }
        abortRecovery = nil
        journal = result; journalSources = result.value.sources; reviewItems = result.value.items
        sources = result.value.sources.filter { !$0.state.isTerminal }.map {
            .init(itemID: $0.itemID, input: $0.input, ready: $0.state == .ready)
        }
        nextOrdinal = (result.value.sources.map { $0.input.itemIndex }.max() ?? -1) + 1
        frozenPlan = nil; frozenContext = nil; prepared = nil; preparedItems = nil
        try requireCurrent(); try Task.checkCancellation()
    }

    /// Freezes the whole observation once, including optional descriptions and
    /// current ordering. A retry cannot substitute a later visible composition.
    func freeze(_ plan: CaptureInitialEvidencePlan) throws {
        try requireCurrent()
        guard !isBusy, plan.ownerID == identity.ownerID, plan.scanID == identity.scanID,
              plan.generation == identity.generation else { throw SharedMediaStorageFailure.closed }
        if let frozenPlan {
            guard frozenPlan == plan else { throw SharedMediaStorageFailure.conflict }
            return
        }
        try requireEditable()
        guard !sources.isEmpty, sources.allSatisfy(\.ready) else { throw SharedMediaStorageFailure.closed }
        let originals = plan.uploads.filter { $0.role.rawValue.hasPrefix("source_") }
        guard Set(originals.map { $0.artifact.mediaID }) == Set(sources.map { $0.input.mediaID }) else {
            throw SharedMediaStorageFailure.conflict
        }
        for source in sources {
            let input = try plan.artifactInput(mediaID: source.input.mediaID, id: source.input.id)
            guard input.role == source.input.role, input.contentType == source.input.contentType,
                  input.byteCount == source.input.byteCount, input.sha256 == source.input.sha256 else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        frozenPlan = plan
    }

    /// The whole saved composition is authoritative. A resumed frozen plan is
    /// returned intact; it must never be reconstructed from review previews.
    func prepareReview() async throws -> CaptureInitialEvidencePlan {
        try requireCurrent(); try Task.checkCancellation()
        guard !isBusy else { throw SharedMediaStorageFailure.closed }
        if let frozenPlan { return frozenPlan }
        try requireEditable()
        guard let journal else { throw SharedMediaStorageFailure.closed }
        isBusy = true
        let items: [CaptureInitialEvidencePreparation.Item]
        do {
            items = try await CaptureInitialJournalPreparation().items(journal: journal.value) { [self] input in
                try await readForPreparation(input)
            }
            try requireCurrent(); try Task.checkCancellation()
        } catch { isBusy = false; throw error }
        isBusy = false
        return try await prepare(items: items)
    }

    func prepare(items: [CaptureInitialEvidencePreparation.Item]) async throws -> CaptureInitialEvidencePlan {
        try requireCurrent()
        guard !isBusy else { throw SharedMediaStorageFailure.closed }
        if let prepared {
            guard preparedItems == items else { throw SharedMediaStorageFailure.conflict }
            return prepared.plan
        }
        try requireEditable()
        guard !sources.isEmpty, sources.allSatisfy(\.ready) else { throw SharedMediaStorageFailure.closed }
        isBusy = true; defer { isBusy = false }
        reviewItems = try journalItems(for: items)
        try await saveJournal(try await admittedOwner())
        let result = try await CaptureInitialEvidencePreparation().prepare(identity: identity, items: items) { [self] input in
            try await readForPreparation(input)
        }
        try requireCurrent(); try Task.checkCancellation()
        // No suspension separates releasing the edit lock and freezing all
        // source membership. The UI cannot submit a partial prepared prefix.
        isBusy = false
        try freeze(result.plan)
        prepared = result; preparedItems = items
        return result.plan
    }

    /// Funding/context are frozen before the first durable submission write.
    /// Lost acknowledgements retry the same plan and cannot release originals.
    func submit(using admission: CaptureInitialSubmissionAccess,
                makeContext: @escaping (CaptureInitialEvidencePlan, ScanFundingReservation) throws -> SharedMediaCaptureSubmissionContext) async throws -> SharedMediaCaptureSubmissionAcceptance {
        try requireCurrent(); try Task.checkCancellation()
        guard !isBusy, let plan = frozenPlan, prepared?.plan == plan else { throw SharedMediaStorageFailure.closed }
        isBusy = true
        do {
            let owner = try await admittedOwner()
            try await admission.prepare(owner)
            try requireCurrent(); try Task.checkCancellation()
        } catch { isBusy = false; throw error }
        isBusy = false
        let context = try admission.begin(plan, frozenContext, makeContext)
        defer { admission.end(plan.scanID) }
        try context.validate(plan: plan)
        guard frozenContext == nil || frozenContext == context else { throw SharedMediaStorageFailure.conflict }
        // Retain even when acceptance fails before its first await. Nothing
        // after this point proves that a durable acceptance did not commit.
        frozenContext = context
        defer { admission.acceptanceAttemptFinished() }
        let receipt = try await accept(context: context)
        try requireCurrent(); try Task.checkCancellation()
        return receipt
    }

    func accept(context: SharedMediaCaptureSubmissionContext) async throws -> SharedMediaCaptureSubmissionAcceptance {
        try requireCurrent(); try Task.checkCancellation()
        guard !isBusy, let prepared, frozenPlan == prepared.plan else { throw SharedMediaStorageFailure.closed }
        try context.validate(plan: prepared.plan)
        if let frozenContext {
            guard frozenContext == context else { throw SharedMediaStorageFailure.conflict }
        } else { frozenContext = context }
        isBusy = true; defer { isBusy = false }
        let owner = try await admittedOwner()
        let result = try await owner.acceptAppCaptureDraft(plan: prepared.plan, context: context, expectedJournal: journal) { input in
            guard let bytes = prepared.derivatives[input.mediaID], bytes.count == input.byteCount,
                  SharedMediaAcquisitionEncoding.digest(bytes) == input.sha256 else {
                throw SharedMediaStorageFailure.conflict
            }
            return bytes
        }
        try requireCurrent(); try Task.checkCancellation()
        return result
    }

    private func readForPreparation(_ input: SharedMediaCaptureDraftSourceInput) async throws -> Data {
        try requireCurrent()
        guard isBusy, sources.contains(where: { $0.input == input && $0.ready }) else { throw SharedMediaStorageFailure.closed }
        let owner = try await admittedOwner()
        let bytes = try await owner.readAppCaptureSource(input)
        try requireCurrent(); try Task.checkCancellation()
        return bytes
    }

    private func admittedOwner() async throws -> SharedMediaNativeOriginalOwner {
        try requireCurrent()
        let resolved = try await resolveOwner()
        try requireCurrent()
        if let owner {
            guard owner === resolved else { throw SharedMediaStorageFailure.stale }
        } else { owner = resolved }
        return resolved
    }

    private func saveJournal(_ owner: SharedMediaNativeOriginalOwner) async throws {
        if let journal, journal.value.sources == journalSources, journal.value.items == reviewItems { return }
        journal = try await owner.saveAppCaptureDraftJournal(scanID: identity.scanID, generation: identity.generation,
            replacing: journal, sources: journalSources, items: reviewItems,
            phase: journal?.value.phase == .discarding ? .discarding : .editing)
        try requireCurrent()
    }

    private func retainReviewItem(itemID: UUID, input: SharedMediaCaptureDraftSourceInput, review: Review?) throws {
        let item: SharedMediaCaptureDraftJournal.Item
        switch (input.role, review) {
        case let (.sourceImage, .photo(recipe)):
            item = .photo(id: itemID, source: input.id, recipe: recipe)
        case (.sourceAudio, nil): item = .audio(id: itemID, source: input.id)
        case let (.sourceVideo, .video(recipe)):
            let companion = journalSources.first { $0.itemID == itemID && $0.input.role == .sourceCompanionAudio }
            item = .video(id: itemID, source: input.id, companion: companion?.input.id, recipe: recipe)
        case (.sourceCompanionAudio, nil):
            guard let existing = reviewItems.first(where: { $0.id == itemID }),
                  case let .video(id, source, companion, recipe) = existing,
                  companion == nil || companion == input.id else { throw SharedMediaStorageFailure.conflict }
            item = .video(id: id, source: source, companion: input.id, recipe: recipe)
        default: throw SharedMediaStorageFailure.invalid
        }
        if let index = reviewItems.firstIndex(where: { $0.id == itemID }) {
            guard reviewItems[index] == item || input.role == .sourceCompanionAudio else { throw SharedMediaStorageFailure.conflict }
            reviewItems[index] = item
        } else { reviewItems.append(item) }
    }

    private func journalItems(for items: [CaptureInitialEvidencePreparation.Item]) throws -> [SharedMediaCaptureDraftJournal.Item] {
        let retainedSources = sources
        return try items.enumerated().map { index, item in
            func id(_ input: SharedMediaCaptureDraftSourceInput) throws -> UUID {
                guard let source = retainedSources.first(where: { $0.input == input && $0.ready }) else { throw SharedMediaStorageFailure.conflict }
                return source.itemID
            }
            switch item {
            case let .photo(source, recipe): return try .photo(id: id(source), source: source.id, recipe: recipe)
            case let .audio(source): return try .audio(id: id(source), source: source.id)
            case let .video(source, _, _, companion):
                let itemID = try id(source)
                guard let existing = reviewItems.first(where: { $0.id == itemID }),
                      case let .video(_, retained, retainedCompanion, recipe) = existing,
                      retained == source.id, retainedCompanion == companion?.id else { throw SharedMediaStorageFailure.conflict }
                return .video(id: itemID, source: source.id, companion: companion?.id, recipe: recipe)
            case let .description(text):
                if reviewItems.indices.contains(index), case let .description(id, saved) = reviewItems[index], saved == text {
                    return .description(id: id, text: text)
                }
                return .description(id: UUID(), text: text)
            }
        }
    }

    private func requireEditable() throws {
        try requireCurrent(); try Task.checkCancellation()
        guard !isBusy, frozenPlan == nil, abortRecovery == nil, journal == nil || journal?.value.phase == .editing,
              !journalSources.contains(where: { $0.state == .discarding }) else { throw SharedMediaStorageFailure.closed }
    }

    private static func abortOnly(_ handle: SharedMediaCaptureAbortRecovery.Handle, owner: SharedMediaNativeOriginalOwner,
                                  ownerID: UUID, requireCurrent: @escaping () throws -> Void,
                                  resolveOwner: @escaping () async throws -> SharedMediaNativeOriginalOwner) -> CaptureInitialDraftSession {
        let session = CaptureInitialDraftSession(identity: .init(ownerID: ownerID, scanID: handle.scanID, generation: handle.generation),
            requireCurrent: requireCurrent, resolveOwner: resolveOwner)
        session.owner = owner; session.abortRecovery = handle
        return session
    }
}

private actor CaptureInitialSourceHasher {
    func digest(_ bytes: Data) throws -> String {
        try Task.checkCancellation()
        guard !bytes.isEmpty, bytes.count <= 33_554_432 else { throw SharedMediaStorageFailure.capacity }
        return SharedMediaAcquisitionEncoding.digest(bytes)
    }
}
