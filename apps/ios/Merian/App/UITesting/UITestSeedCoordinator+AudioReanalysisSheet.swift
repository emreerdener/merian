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
        let access = CaptureAudioReanalysisAccess.prepared(account: seed.cloud, ownership: .init(),
            configuration: .init(authorize: { _, validate in
                try validate(); return .init(recipient: .gemini, validate: validate)
            }, start: { [weak self] key, proof, candidate, _ in
                guard let self, candidate === container else { return .unavailable }
                do {
                    let saved = try ObservationAudioExecutionStore.read(proof, container: candidate, isCurrent: { true })
                    guard saved == key.snapshot, original == nil || original == saved,
                          try ModelContext(candidate).fetchCount(FetchDescriptor<OfflineQueuedScan>()) == 1 else {
                        savedIdentity = "Persistence mismatch"; return .unavailable
                    }
                    original = saved
                    savedIdentity = saved.work.intent.request.analysisID.uuidString.lowercased()
                } catch { savedIdentity = "Persistence failure" }
                // No provider, upload, receipt fabrication or consumption; the exact bound request stays durable.
                return .unavailable
            }), currentOwner: { owner }, generation: { 1 },
            sessionIsCurrent: { $0.userID == owner && !$0.isAnonymous },
            containerIsCurrent: { $0 === container }, documents: { root })
        host = try CaptureAudioReanalysisHost(opened: access.open(
            .init(observationID: observation, analysisID: analysis, ownerID: owner), container, UUID()))
    }

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
                }
                .padding().background(.regularMaterial)
            }
        }
        .sheet(isPresented: Binding(get: { fixture?.host?.isPresented == true }, set: { if !$0 { fixture?.host?.close() } })) {
            if let fixture, let host = fixture.host { CaptureAudioReanalysisSheet(host: host, preparer: fixture.preparer) }
        }
    }
}
#endif
