import SwiftUI

struct IdentificationHistorySheet: View {
    @Bindable var model: IdentificationHistoryViewModel
    var candidateRendering = CandidateReviewRendering()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPhoto: UUID?
    @State private var retainedCandidates: AnalysisCandidateReviewModel?
    @State private var candidates: AnalysisCandidateReviewModel?

    var body: some View {
        NavigationStack {
            List {
                if model.isClosed { Text("History is no longer available for this account.") }
                else if let detail = model.detail { preview(detail) }
                else {
                    Section {
                        ForEach(model.rows) { row in
                            Button { model.start(.preview(row.id)) } label: { rowLabel(row) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("HistoryRow_\(row.id.uuidString.lowercased())")
                        }
                    } footer: { Text("Tap an identification to preview it. Viewing an entry does not change your scan.") }
                    if model.rows.isEmpty && !model.isBusy { Text("No history entries loaded.") }
                    if model.nextBeforeOrdinal != nil {
                        Button("Earlier identifications") { model.start(.older) }.accessibilityIdentifier("HistoryEarlier")
                    }
                    if model.showingOlder {
                        Button("Newest identifications") { model.start(.newest) }.accessibilityIdentifier("HistoryNewest")
                    }
                }
                if model.pending {
                    Section {
                        Label("Change pending", systemImage: "clock")
                        Button("Retry change") { model.start(.retry) }.accessibilityIdentifier("HistoryRetry")
                    } footer: { Text("The current identification stays visible until your change is acknowledged.") }
                }
                if let message = model.message { Text(message).font(.callout).accessibilityIdentifier("HistoryMessage") }
                if model.undoOperation != nil {
                    Button("Undo identification change") { model.start(.undo) }.accessibilityIdentifier("HistoryUndo")
                }
                if model.isBusy { ProgressView().accessibilityLabel("Loading identification history") }
            }
            .disabled(model.isBusy)
            .navigationTitle(model.detail == nil ? "Identification history" : "Identification preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if model.detail != nil {
                        Button("History", systemImage: "chevron.left") { model.back(); selectedPhoto = nil }
                            .disabled(model.isBusy)
                            .accessibilityIdentifier("HistoryBack")
                    } else {
                        Button("Refresh", systemImage: "arrow.clockwise") { model.start(.newest) }.disabled(model.isBusy || model.isClosed)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.close(); dismiss() }.accessibilityIdentifier("HistoryDone")
                }
            }
        }
        .accessibilityIdentifier("IdentificationHistorySheet")
        .presentationDetents([.large])
        .sheet(item: $candidates, onDismiss: { retainedCandidates?.close(); retainedCandidates = nil }) { candidate in
            AnalysisCandidateReviewSheet(model: candidate, rendering: candidateRendering)
        }
        .task { if model.rows.isEmpty && model.detail == nil { model.start(.newest) } }
        .onChange(of: model.isSessionCurrent, initial: true) { _, current in if !current { model.close() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshReview() } }
        .onChange(of: model.reviewDeliveryGeneration) { _, _ in model.refreshReview() }
        .onChange(of: model.review?.terminalMessage) { _, value in if value != nil { model.refreshReview() } }
        .task(id: model.undoOperation) { await model.expireUndo() }
        .task(id: selectedPhoto) { if let selectedPhoto { await model.loadPhoto(selectedPhoto) } }
        .onChange(of: model.detail?.row.id) { _, _ in selectedPhoto = nil }
        // The owning shell closes this session on actual dismissal. A nested
        // candidate sheet may cover History without ending its review scope.
    }
    private func rowLabel(_ row: IdentificationHistoryRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.headline)
                if model.selected == row.id { Label("Current", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.tint) }
            }
            if let scientific = row.scientificName, scientific != row.title { Text(scientific).italic() }
            if let date = row.completedAt { Text(date, format: .dateTime.year().month().day().hour().minute()).font(.caption) }
            else { Text("Saved identification · Original date unavailable").font(.caption) }
            Text([row.confidence, row.review].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
    @ViewBuilder private func preview(_ detail: IdentificationHistoryDetail) -> some View {
        Section { rowLabel(detail.row) }
        Section {
            if model.selected == detail.row.id { Text("This is your current identification.") }
            else {
                Button("Use this identification") { model.start(.restore) }
                    .disabled(!detail.canRestore || model.pending)
                    .accessibilityIdentifier("HistoryRestore")
                if let reason = detail.restoreUnavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
            }
        } footer: {
            Text("Choosing this entry keeps the entire history. It does not confirm a species, clear an incorrect mark, or update a shared post.")
        }
        if let review = model.review { IdentificationHistoryReviewSection(model: review, onReviewCandidates: {
            let candidate = model.prepareCandidateReview()
            retainedCandidates = candidate; candidates = candidate
        }).id(ObjectIdentifier(review)) }
        if let publication = model.publication {
            IdentificationPublicationSection(model: publication).id(ObjectIdentifier(publication))
        } else if model.canAskCommunity {
            Section {
                Button("Ask the community") { model.askCommunity() }
                    .accessibilityIdentifier("HistoryAskCommunity")
            }
        }
        if model.canReanalyze {
            Section {
                Button("Reanalyze from this identification") { model.start(.reanalyze) }
                    .accessibilityIdentifier("HistoryReanalyze")
            } footer: { Text("Review the photos and notes before submitting. Your current identification stays selected.") }
        }
        if detail.isCached { Text("Saved preview. Any change will wait for server acknowledgment.").font(.callout) }
        if !detail.canRestore && model.selected != detail.row.id {
            Text("Reconnect and refresh this preview before using it. Some older entries may not have enough saved detail to restore.").font(.callout)
        }
        if let reasoning = detail.reasoning { Section("Identification reasoning") { Text(reasoning) } }
        if !detail.alternatives.isEmpty {
            Section("Alternatives in this result") { ForEach(Array(detail.alternatives.enumerated()), id: \.offset) { _, name in Text(name) } }
        }
        Section("Evidence used") {
            if detail.row.isImported { Text("Original evidence is unavailable for this saved identification.") }
            if let description = detail.evidenceDescription { Text(description) }
            if !detail.photoIDs.isEmpty {
                ForEach(Array(detail.photoIDs.enumerated()), id: \.element) { index, id in
                    Button("View evidence photo \(index + 1)") { selectedPhoto = id }
                        .accessibilityIdentifier("HistoryPhoto_\(index)")
                }
                if let photo = model.photo { Image(uiImage: photo).resizable().scaledToFit().accessibilityLabel("Evidence used for this identification") }
            }
            if !detail.row.isImported && detail.photoIDs.isEmpty && detail.evidenceDescription == nil {
                Text("No viewable evidence is available in this preview.")
            }
        }
    }
}
