import Foundation

/// Recoverable review state, never a file or submission capability. Every
/// source identity is allocated before its original can be materialized.
struct SharedMediaCaptureDraftJournal: Codable, Equatable, Sendable {
    enum Format: String, Codable, Sendable { case v1 = "captureDraftJournalV1" }
    enum Phase: String, Codable, Sendable { case editing, preparing, abortingPreparation, submitting, accepted, discarding, released }
    enum SourceState: String, Codable, Sendable {
        case pending, ready, discarding, released, releasedWithoutReservationV1
        var isTerminal: Bool { self == .released || self == .releasedWithoutReservationV1 }
    }
    struct Source: Codable, Equatable, Sendable {
        let itemID: UUID
        let input: SharedMediaCaptureDraftSourceInput
        var state: SourceState
    }
    struct VideoRecipe: Codable, Equatable, Sendable {
        let duration: Double
        let isPro: Bool
        let composingCenter: Double
        let scale: Double
        let offsetX: Double
        let offsetY: Double
        let displaySize: Double?
        let quarterTurns: Int
        func validate() throws {
            guard duration.isFinite, duration > 0,
                  composingCenter.isFinite, (0...1).contains(composingCenter),
                  scale.isFinite, scale >= 1, offsetX.isFinite, offsetY.isFinite,
                  (0...3).contains(quarterTurns) else { throw SharedMediaStorageFailure.invalid }
            if let displaySize {
                guard displaySize.isFinite, displaySize > 0 else { throw SharedMediaStorageFailure.invalid }
            } else {
                guard scale == 1, offsetX == 0, offsetY == 0, quarterTurns == 0 else { throw SharedMediaStorageFailure.invalid }
            }
        }
    }
    enum Item: Codable, Equatable, Sendable {
        case photo(id: UUID, source: UUID, recipe: SharedMediaNativePreparationRecipe)
        case audio(id: UUID, source: UUID)
        case video(id: UUID, source: UUID, companion: UUID?, recipe: VideoRecipe)
        case description(id: UUID, text: String)
        var id: UUID {
            switch self {
            case let .photo(id, _, _), let .audio(id, _), let .video(id, _, _, _), let .description(id, _): return id
            }
        }
        var sourceIDs: [UUID] {
            switch self {
            case let .photo(_, source, _), let .audio(_, source): return [source]
            case let .video(_, source, companion, _): return [source] + (companion.map { [$0] } ?? [])
            case .description: return []
            }
        }
    }
    // A bounded context (1 MiB), base64 frozen plan (<1.4 MiB), and
    // duplicated description text (<=192 KiB escaped) fit with identity headroom.
    static let maximumBytes = 3 * Int(PhotoPreparationPolicy.metadata)
    let format: Format
    let profile: SharedMediaNativeAppProfile
    let rootBindingSHA256: String
    let scanID: UUID
    let generation: UUID
    let revision: Int64
    let phase: Phase
    let sources: [Source]
    let items: [Item]
    /// Persisted only when the whole observation is frozen. No retry prepares
    /// a new observation from changed UI or remints derivative identities.
    let frozenObservation: SharedMediaNativePreparationBlob?
    let frozenContext: SharedMediaCaptureSubmissionContext?
    var preparation: SharedMediaCapturePreparedAttempt?
    var abortedPreparations: [SharedMediaCaptureAbortedPreparation]?

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(self)
        guard bytes.count <= Self.maximumBytes else { throw SharedMediaStorageFailure.capacity }
        return bytes
    }
    static func decode(_ bytes: Data, sha256: String) throws -> Self {
        guard !bytes.isEmpty, bytes.count <= maximumBytes,
              SharedMediaAcquisitionEncoding.digest(bytes) == sha256 else { throw SharedMediaStorageFailure.conflict }
        let result = try JSONDecoder().decode(Self.self, from: bytes)
        guard try result.encoded() == bytes else { throw SharedMediaStorageFailure.conflict }
        return result
    }
    func validate() throws {
        _ = try profile.binding
        guard revision >= 0, revision < Int64.max - 4,
              SharedMediaAcquisitionEncoding.isHash(rootBindingSHA256),
              UUID(uuidString: profile.storeIdentity)?.uuidString == profile.storeIdentity,
              [profile.physicalBinding, profile.receiptDigest].allSatisfy(SharedMediaAcquisitionEncoding.isHash),
              sources.count <= 64, items.count <= 64 else { throw SharedMediaStorageFailure.invalid }
        var used = Set([profile.ownerID, profile.inventoryID, profile.generation, scanID, generation])
        guard used.count == 5 else { throw SharedMediaStorageFailure.conflict }
        if let abortedPreparations {
            guard !abortedPreparations.isEmpty, abortedPreparations.count <= 64,
                  Set(abortedPreparations.map(\.attemptSHA256)).count == abortedPreparations.count else {
                throw SharedMediaStorageFailure.conflict
            }
            for attempt in abortedPreparations {
                try attempt.validate()
                for member in attempt.members {
                    guard used.insert(member.artifactID).inserted, used.insert(member.mediaID).inserted else {
                        throw SharedMediaStorageFailure.conflict
                    }
                }
            }
        }
        var ordinals: [UUID: Int] = [:], ordinalItems: [Int: UUID] = [:], roles: Set<String> = []
        for source in sources {
            let input = source.input
            guard input.scanID == scanID, input.submissionGeneration == generation,
                  (0..<64).contains(input.itemIndex), SharedMediaAcquisitionEncoding.isHash(input.sha256),
                  used.insert(input.id).inserted, used.insert(input.mediaID).inserted,
                  roles.insert(source.itemID.uuidString + input.role.rawValue).inserted,
                  ordinals[source.itemID].map({ $0 == input.itemIndex }) ?? true,
                  ordinalItems[input.itemIndex].map({ $0 == source.itemID }) ?? true else { throw SharedMediaStorageFailure.conflict }
            ordinals[source.itemID] = input.itemIndex; ordinalItems[input.itemIndex] = source.itemID
            try input.context.validate(role: input.role)
            try input.role.require(contentType: input.contentType, byteCount: input.byteCount, frameIndex: nil)
        }
        var represented: Set<UUID> = [], itemIDs: Set<UUID> = []
        var descriptionUnits = 0
        func member(_ id: UUID, item: UUID, role: SharedMediaCaptureArtifactRequest.Role) throws {
            guard represented.insert(id).inserted,
                  let source = sources.first(where: { $0.input.id == id }),
                  source.itemID == item, source.input.role == role, !source.state.isTerminal else {
                throw SharedMediaStorageFailure.conflict
            }
        }
        for item in items {
            guard itemIDs.insert(item.id).inserted, !used.contains(item.id) else { throw SharedMediaStorageFailure.conflict }
            switch item {
            case let .photo(id, source, recipe):
                try member(source, item: id, role: .sourceImage); try recipe.validate()
            case let .audio(id, source): try member(source, item: id, role: .sourceAudio)
            case let .video(id, source, companion, recipe):
                try member(source, item: id, role: .sourceVideo); try recipe.validate()
                if let companion { try member(companion, item: id, role: .sourceCompanionAudio) }
            case let .description(_, text):
                guard ObservationHistoryAudioReference.hasDescriptionContent(text),
                      !text.unicodeScalars.contains(where: { $0.value == 0 }),
                      text.unicodeScalars.count <= 8192, text.utf16.count <= 16_384,
                      text.utf16.count <= 32_000 - descriptionUnits else {
                    throw SharedMediaStorageFailure.invalid
                }
                descriptionUnits += text.utf16.count
            }
        }
        guard represented == Set(sources.filter { !$0.state.isTerminal }.map { $0.input.id }) else {
            throw SharedMediaStorageFailure.conflict
        }
        let active = sources.filter { !$0.state.isTerminal }
        let photos = active.filter { $0.input.role == .sourceImage }
        let videos = active.filter { $0.input.role == .sourceVideo }
        let audios = active.filter { $0.input.role == .sourceAudio }
        let companions = active.filter { $0.input.role == .sourceCompanionAudio }
        let physical = photos.count + videos.count + audios.count
        guard physical > 0 || phase == .released,
              physical <= (physical == photos.count ? 5 : 2), videos.count <= 1,
              audios.count + companions.count <= 2,
              photos.reduce(Int64(0), { $0 + $1.input.byteCount }) <= 67_108_864 else {
            throw SharedMediaStorageFailure.capacity
        }
        switch phase {
        case .editing, .discarding, .released:
            guard frozenObservation == nil, frozenContext == nil, preparation == nil else { throw SharedMediaStorageFailure.conflict }
            if phase == .discarding {
                guard sources.allSatisfy({ $0.state == .discarding || $0.state.isTerminal }) else { throw SharedMediaStorageFailure.conflict }
            }
            if phase == .released {
                guard items.isEmpty, sources.allSatisfy({ $0.state.isTerminal }) else { throw SharedMediaStorageFailure.conflict }
            }
        case .preparing, .abortingPreparation:
            guard frozenObservation == nil, frozenContext == nil, let preparation,
                  sources.filter({ !$0.state.isTerminal }).allSatisfy({ $0.state == .ready }) else {
                throw SharedMediaStorageFailure.conflict
            }
            try preparation.validate(journal: self)
        case .submitting, .accepted:
            guard preparation == nil else { throw SharedMediaStorageFailure.conflict }
            guard let frozenObservation, let frozenContext, !items.isEmpty,
                  sources.filter({ !$0.state.isTerminal }).allSatisfy({ $0.state == .ready }) else { throw SharedMediaStorageFailure.conflict }
            try frozenObservation.validate()
            let plan = try CaptureInitialEvidencePlan(ownerID: profile.ownerID, data: frozenObservation.bytes)
            guard try plan.encoded() == frozenObservation.bytes, plan.scanID == scanID,
                  plan.generation == generation else { throw SharedMediaStorageFailure.conflict }
            try frozenContext.validate(plan: plan)
            try requirePlan(plan)
        }
    }
    func requirePlan(_ plan: CaptureInitialEvidencePlan) throws {
        guard plan.items.count == items.count else { throw SharedMediaStorageFailure.conflict }
        let active = sources.filter { !$0.state.isTerminal }
        let originals = plan.uploads.filter { $0.role.rawValue.hasPrefix("source_") }
        guard Set(originals.map { $0.artifact.mediaID }) == Set(active.map { $0.input.mediaID }) else { throw SharedMediaStorageFailure.conflict }
        for source in active {
            let expected = try plan.artifactInput(mediaID: source.input.mediaID, id: source.input.id)
            guard expected.role == source.input.role, expected.contentType == source.input.contentType,
                  expected.byteCount == source.input.byteCount, expected.sha256 == source.input.sha256 else { throw SharedMediaStorageFailure.conflict }
        }
        for (item, node) in zip(items, plan.items) {
            switch (item, node) {
            case let (.description(_, text), .description(saved)):
                guard text == saved else { throw SharedMediaStorageFailure.conflict }
            case let (.photo(_, source, recipe), .image(original, _, _, preparation)):
                guard sources.first(where: { $0.input.id == source })?.input.mediaID == original.mediaID,
                      try ObservationInitialPhotoPreparation(recipe: recipe) == preparation else { throw SharedMediaStorageFailure.conflict }
            case let (.audio(_, source), .audio(audio)):
                guard sources.first(where: { $0.input.id == source })?.input.mediaID == audio.source.mediaID else { throw SharedMediaStorageFailure.conflict }
            case let (.video(_, source, companion, _), .video(video)):
                guard sources.first(where: { $0.input.id == source })?.input.mediaID == video.source.mediaID,
                      companion.flatMap({ id in sources.first(where: { $0.input.id == id })?.input.mediaID }) == video.audio?.source.mediaID else { throw SharedMediaStorageFailure.conflict }
            default: throw SharedMediaStorageFailure.conflict
            }
        }
    }
}
