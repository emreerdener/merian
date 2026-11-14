import SwiftData
import SwiftUI

/// Resolves a value-only scan route after its presentation has mounted, then
/// constructs Insight only after the exact local record has hydrated the shared
/// inference engine. This keeps record loading out of tap handlers and prevents
/// stale Insight content from appearing during navigation transitions.
struct LocalScanInsightLoader<Content: View>: View {
    private enum Phase: Equatable {
        case loading
        case loaded
        case unavailable
    }

    @Environment(AppDIContainer.self) private var diContainer
    @Environment(InferenceEngine.self) private var inferenceEngine
    @Environment(\.modelContext) private var modelContext

    let scanId: String
    private let content: () -> Content

    @State private var phase: Phase = .loading

    init(
        scanId: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.scanId = scanId
        self.content = content
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView("Loading scan")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("LocalScanInsightLoading")
            case .loaded:
                content()
            case .unavailable:
                ContentUnavailableView(
                    "Scan unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("This scan is no longer in your library.")
                )
                .accessibilityIdentifier("LocalScanInsightUnavailable")
            }
        }
        .background(Color(uiColor: .systemBackground))
        .task(id: scanId) {
            await loadRecord()
        }
    }

    @MainActor
    private func loadRecord() async {
        phase = .loading
        let generation = inferenceEngine.scanPresentationGeneration

        // Commit the sheet or navigation destination before touching SwiftData
        // or the inference engine so the originating surface stays responsive.
        await Task.yield()
        guard !Task.isCancelled else { return }

        let requestedScanId = scanId
        var descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { $0.id == requestedScanId }
        )
        descriptor.fetchLimit = 1

        do {
            // Return only scalar ownership from this scope; never retain the
            // managed record across native media I/O.
            let authority: SharedMediaConsumerAuthority = try {
                guard let record = try modelContext.fetch(descriptor).first else { throw SharedMediaStorageFailure.stale }
                return try SharedMediaConsumerAuthority.classify(raw: record.mediaAuthorityRaw,
                    consumerID: record.sharedMediaConsumerID, record: .scan)
            }()
            if case .nativeInitial(let bindingID) = authority {
                let container = modelContext.container
                try await NativeInitialInsightMedia.app(scanID: requestedScanId, bindingID: bindingID,
                    container: container, di: diContainer,
                    isPresentedCurrent: { !Task.isCancelled && inferenceEngine.scanPresentationGeneration == generation },
                    publish: { media in
                        guard try NativeInitialInsightMedia.binding(scanID: requestedScanId, container: container) == bindingID else {
                            throw SharedMediaStorageFailure.stale
                        }
                        let freshContext = ModelContext(container)
                        guard let fresh = try freshContext.fetch(descriptor).first else { throw SharedMediaStorageFailure.stale }
                        inferenceEngine.load(from: fresh, retainedDisplayMedia: media)
                    })
            } else {
                guard let record = try modelContext.fetch(descriptor).first else { throw SharedMediaStorageFailure.stale }
                inferenceEngine.load(from: record)
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .unavailable; return
        }
        guard !Task.isCancelled else { return }
        phase = .loaded
    }
}
