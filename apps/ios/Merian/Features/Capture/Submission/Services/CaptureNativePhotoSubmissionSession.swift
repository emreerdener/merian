import Foundation

/// One immutable native selection and one retained admitted owner. Ordinary
/// composition provides no session. Receipt is local and leaves work held.
@MainActor
final class CaptureNativePhotoSubmissionSession {
    typealias Validator = @MainActor @Sendable () throws -> Void
    typealias Preflight = @MainActor (IdentificationPreflightInput, UUID, @escaping Validator) async throws -> IdentificationDispatchAuthorization
    let selection: CaptureNativePhotoSubmissionSelection
    private let resolveOwner: () async throws -> SharedMediaNativeOriginalOwner
    private let preflight: Preflight?
    private var owner: SharedMediaNativeOriginalOwner?
    private var frozen: CaptureNativePhotoSubmissionSnapshot?
    private(set) var prepared: SharedMediaNativeReceivingIntent.Prepared?
    private(set) var receipt: SharedMediaNativeConsumerCohort?
    private(set) var isBusy = false
    private(set) var attemptID: UUID?

    init(selection: CaptureNativePhotoSubmissionSelection,
         preflight: Preflight? = nil,
         resolveOwner: @escaping () async throws -> SharedMediaNativeOriginalOwner) {
        self.selection = selection; self.preflight = preflight; self.resolveOwner = resolveOwner
    }

    static func app(selection: CaptureNativePhotoSubmissionSelection, diContainer: AppDIContainer) -> CaptureNativePhotoSubmissionSession {
        .init(selection: selection, preflight: appPreflight,
              resolveOwner: { try await diContainer.nativeMediaOwnerForFeature() })
    }

    static var appPreflight: Preflight {
        { input, ownerID, validate in
            try await MerianNetworkClient.shared.prepareNativePhotoAdmissionAuthorization(
                input: input, expectedAuthUserID: ownerID, validateAttempt: validate)
        }
    }

    /// No automatic retry. A second explicit call discovers before staging and
    /// can recover only this session's original immutable selection.
    func submit(_ snapshot: CaptureNativePhotoSubmissionSnapshot) async throws -> UUID {
        guard !isBusy else { throw SharedMediaStorageFailure.closed }
        try selection.validate(snapshot)
        guard frozen == nil || frozen == snapshot else { throw SharedMediaStorageFailure.stale }
        frozen = snapshot
        let attempt = UUID(); attemptID = attempt; isBusy = true
        defer { isBusy = false }
        try Task.checkCancellation()
        let admitted: SharedMediaNativeOriginalOwner
        if let owner { admitted = owner }
        else { admitted = try await resolveOwner(); owner = admitted }
        try Task.checkCancellation()
        let saved = try await admitted.discoverAppReceivingSlot(packageID: selection.identity.packageID)
        let selected: SharedMediaNativeReceivingIntent.Prepared
        if let saved {
            switch try SharedMediaNativeReceivingSlot.decode(saved, profile: selection.metadata.profile) {
            case .prepared(let value): selected = value
            case .received(let value, _, let transaction):
                try requireExact(value)
                prepared = value; receipt = transaction.cohort
                return attempt
            case .abandoned: throw SharedMediaStorageFailure.closed
            }
        } else {
            guard prepared == nil, receipt == nil else { throw SharedMediaStorageFailure.stale }
            try Task.checkCancellation()
            selected = try await stage(admitted, snapshot: snapshot)
        }
        try requireExact(selected)
        prepared = selected
        try Task.checkCancellation()
        receipt = try await admitted.receiveAppPrepared(selected)
        return attempt
    }

    private func stage(_ owner: SharedMediaNativeOriginalOwner,
                       snapshot: CaptureNativePhotoSubmissionSnapshot) async throws -> SharedMediaNativeReceivingIntent.Prepared {
        guard let preflight else {
            return try await owner.stageAppReceiving(packageID: selection.identity.packageID,
                draftGeneration: selection.identity.draftGeneration, pairIDs: selection.pairIDs,
                expectedMetadata: selection.metadata)
        }
        let supporting: SharedMediaNativeFrozenSupporting = try SharedMediaAcquisitionEncoding.decode(
            selection.supportingBytes, maximum: Int(PhotoPreparationPolicy.metadata))
        return try await owner.stageAppReceivingWithAdmission(metadata: selection.metadata, pairIDs: selection.pairIDs) { [self] observationID in
            try selection.validate(snapshot)
            let input = try IdentificationPreflightInput(nativePhotoObservationID: observationID,
                photoCount: selection.pairIDs.count, contexts: supporting.contexts)
            let validate: Validator = {
                try Task.checkCancellation()
                try self.selection.validate(snapshot)
                guard self.frozen == snapshot else { throw SharedMediaStorageFailure.stale }
            }
            let authorization = try await preflight(input, selection.identity.ownerID, validate)
            try validate()
            return IdentificationDispatchAuthorization(recipient: authorization.recipient) {
                try authorization.validate(); try validate()
            }
        }
    }

    private func requireExact(_ value: SharedMediaNativeReceivingIntent.Prepared) throws {
        try selection.validate(value)
        if let prepared, try prepared.encoded() != value.encoded() { throw SharedMediaStorageFailure.stale }
    }
}
