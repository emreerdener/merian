#if DEBUG
import Foundation
import Observation
import SwiftData
import SwiftUI

extension UITestSeedCoordinator {
    static var audioReanalysisSheetEnabled: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-seedAudioReanalysisSheet")
    }
    @MainActor static var audioReanalysisSheetFixture: AudioReanalysisSheetUIFixture?
}

/// Real local enrollment, preparation and binding; only account and dispatch boundaries are synthetic.
@MainActor @Observable
final class AudioReanalysisSheetUIFixture {
    let container: ModelContainer
    let root: URL
    let source: URL
    let preparer: CaptureAudioInputPreparer
    private(set) var host: CaptureAudioReanalysisHost?
    private(set) var savedIdentity = "No request"
    private(set) var authorizations = 0
    private(set) var starts = 0
    private var accountCurrent = true
    private var bundle: PreparedHistoryReanalysisComposition?
    private var proof: ObservationAudioPreparation.Verified?
    private(set) var savedModel: CaptureAudioSavedRequestsModel?
    private var savedScope: UUID?
    private var original: ObservationAudioExecutionStore.Snapshot?

    init(container: ModelContainer) throws {
        self.container = container
        root = FileManager.default.temporaryDirectory.appendingPathComponent("audio-sheet-\(UUID())", isDirectory: true)
        source = root.appendingPathComponent("input.wav")
        preparer = .init(directory: root.appendingPathComponent("conversion", isDirectory: true))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try UITestSeedCoordinator.queuedAudioHandoffWAVData().write(to: source, options: .atomic)
    }

    func seed() throws {
        // Reuse the immutable V2 seed, never a private Prepared/Opened initializer or parent media fallback.
        let seed = try PublicationConsentUIFixture(container: container, namedReview: false,
            confirmationUndo: false, candidateConfirmation: false)
        try seed.seed(context: container.mainContext)
        try container.mainContext.save()
        guard let observation = UUID(uuidString: PublicationConsentUIFixture.observation),
              let analysis = UUID(uuidString: PublicationConsentUIFixture.selected) else { throw MerianError.invalidResponse }
        let owner = PublicationConsentUIFixture.owner, container = container, root = root
        let configuration = CaptureAudioReanalysisAccess.Configuration(authorize: { [weak self] _, validate in
                try validate(); self?.authorizations += 1
                return .init(recipient: .gemini, validate: validate)
            }, start: { [weak self] key, proof, candidate, _ in
                guard let self, candidate === container else { return .unavailable }
                do {
                    let saved = try ObservationAudioExecutionStore.read(proof, container: candidate, isCurrent: { true })
                    guard saved == key.snapshot, original == nil || original == saved,
                          try ModelContext(candidate).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1 else {
                        savedIdentity = "Persistence mismatch"; return .unavailable
                    }
                    original = saved; self.proof = proof; starts += 1
                    savedIdentity = saved.work.intent.request.analysisID.uuidString.lowercased()
                } catch { savedIdentity = "Persistence failure" }
                // No provider, upload, receipt fabrication or consumption; the exact bound request stays durable.
                return .unavailable
            })
        let bundle = PreparedHistoryReanalysisComposition(routes: AppRouteCoordinator(), cloud: seed.cloud,
            currentOwner: { [weak self] in self?.accountCurrent == true ? owner : nil }, generation: { 1 },
            sessionIsCurrent: { [weak self] in self?.accountCurrent == true && $0.userID == owner && !$0.isAnonymous },
            preparationOwner: .init(), enrollmentOwner: .init(), containerIsCurrent: { $0 === container },
            submitted: { _ in }, cleanup: {}, audio: configuration, audioStatusOwner: .init(), documents: { root })
        self.bundle = bundle
        host = try bundle.openAudioHost(target: .init(observationID: observation, analysisID: analysis, ownerID: owner), container: container)
    }

    /// Explicit test transition only: emulate an interrupted consumed attempt, then remove its owned WAV.
    func prepareConsumedRecovery() {
        guard accountCurrent, let proof, let original else { return }
        do {
            let claim = try ObservationAudioExecutionStore.claim(original, purpose: .initial, proof: proof,
                container: container, isCurrent: { self.accountCurrent })
            let permit = try ObservationAudioExecutionStore.consume(claim, proof: proof, container: container,
                isCurrent: { self.accountCurrent })
            self.original = permit.snapshot
            try FileManager.default.removeItem(at: root.appendingPathComponent(proof.preparation.path))
        } catch { savedIdentity = "Recovery setup failure" }
    }

    func openSaved() {
        guard savedModel == nil, let bundle, let proof else { return }
        let scope = UUID(); savedScope = scope
        do {
            savedModel = try bundle.openSavedAudioRequests(ownerID: proof.preparation.identity.ownerID,
                observationID: proof.preparation.identity.observationID, container: container,
                isPresented: { [weak self] in self?.savedScope == scope })
        } catch { savedScope = nil; savedIdentity = "Saved presentation failure" }
    }

    func closeSaved() { savedScope = nil; savedModel?.close(); savedModel = nil }
    func loseAccount() { accountCurrent = false }

    func open() {
        guard let host, host.present() else { return }
        if !host.isFrozen { host.prepareInput(from: source, using: preparer) }
    }
}

struct AudioReanalysisSheetUITestPresentation: ViewModifier {
    @State private var fixture = UITestSeedCoordinator.audioReanalysisSheetFixture
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let fixture {
                VStack {
                    Button("Open audio submission") { fixture.open() }.accessibilityIdentifier("AudioFixtureOpen")
                    Text(fixture.savedIdentity).accessibilityIdentifier("AudioFixtureSavedIdentity")
                    Button("Prepare consumed recovery") { fixture.prepareConsumedRecovery() }.accessibilityIdentifier("AudioFixtureConsume")
                    Button("Open saved requests") { fixture.openSaved() }.accessibilityIdentifier("AudioFixtureSavedOpen")
                    Text("\(fixture.starts):\(fixture.authorizations)").accessibilityIdentifier("AudioFixtureCounts")
                }
                .padding().background(.regularMaterial)
            }
        }
        .sheet(isPresented: Binding(get: { fixture?.savedModel != nil }, set: { if !$0 { fixture?.closeSaved() } })) {
            if let fixture, let model = fixture.savedModel {
                CaptureAudioSavedRequestsSheet(model: model).overlay(alignment: .bottom) {
                    Button("End synthetic account") { fixture.loseAccount() }.accessibilityIdentifier("AudioFixtureLoseAccount")
                }
            }
        }
        .sheet(isPresented: Binding(get: { fixture?.host?.isPresented == true }, set: { if !$0 { fixture?.host?.close() } })) {
            if let fixture, let host = fixture.host { CaptureAudioReanalysisSheet(host: host, preparer: fixture.preparer) }
        }
    }
}
#endif
