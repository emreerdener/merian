import SwiftUI

struct IdentificationHistorySheet: View {
    @Bindable var model: IdentificationHistoryViewModel
    var candidateRendering = CandidateReviewRendering()
    var isEmbedded = false
    var onClose: (() -> Void)?
    var onViewReanalysisProgress: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var request: CardRequest?
    @State private var auxiliary: Auxiliary?
    @State private var retainedCandidates: AnalysisCandidateReviewModel?

    private struct CardRequest: Equatable {
        let token = UUID()
        let id: UUID
        let action: IdentificationHistoryViewModel.CardAction
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.token == rhs.token }
    }
    private enum Auxiliary: String, Identifiable {
        case review, community, candidates
        var id: String { rawValue }
    }

    var body: some View {
        navigationContainer {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.isClosed {
                        Text("History is no longer available for this account.")
                    } else {
                        ForEach(model.cardRows) { row in
                            IdentificationHistoryCard(row: row, isCurrent: row.id == model.selected,
                                actionsEnabled: model.canChangeCardScope && request == nil,
                                action: { request = .init(id: row.id, action: $0) },
                                thumbnail: model.thumbnails[row.id],
                                onViewReanalysisProgress: onViewReanalysisProgress,
                                onViewCommunityRequest: onViewCommunityRequest) {
                                currentControls(row)
                            }
                            .task(id: model.thumbnailGeneration) { model.requestCardThumbnail(row.id) }
                            .onDisappear { model.hideCardThumbnail(row.id) }
                        }
                        if model.cardRows.isEmpty && !model.isBusy { Text("No history entries loaded.") }
                        if model.nextBeforeOrdinal != nil {
                            Button("Earlier identifications") { model.start(.older) }
                                .accessibilityIdentifier("HistoryEarlier")
                        }
                        if model.showingOlder {
                            Button("Newest identifications") { model.start(.newest) }
                                .accessibilityIdentifier("HistoryNewest")
                        }
                    }
                    status
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if model.undoOperation != nil {
                            Button("Undo identification change", systemImage: "arrow.uturn.backward") { model.start(.undo) }
                                .accessibilityIdentifier("HistoryUndo")
                        }
                        Button("Refresh", systemImage: "arrow.clockwise") { model.start(.newest) }
                            .disabled(!model.canChangeCardScope)
                        Button("Close") { close() }.accessibilityIdentifier("HistoryDone")
                    } label: { Image(systemName: "ellipsis").foregroundStyle(.primary) }
                    .tint(Color(uiColor: .label))
                    .accessibilityLabel("History actions")
                    .accessibilityIdentifier("HistorySheetActions")
                }
            }
        }
        .accessibilityIdentifier("IdentificationHistorySheet")
        .presentationDetents([.large])
        .sheet(item: $auxiliary, onDismiss: {
            retainedCandidates?.close(); retainedCandidates = nil
            model.returnToCards()
        }) { destination in
            auxiliaryContent(destination)
        }
        .task { model.openCards() }
        .task(id: request) {
            guard let request else { return }
            let result = await model.performCardAction(request.action, id: request.id)
            guard !Task.isCancelled, !model.isClosed, self.request == request else { return }
            switch result {
            case .review: auxiliary = .review
            case .community: auxiliary = .community
            case .candidates:
                retainedCandidates = model.prepareCandidateReview()
                if retainedCandidates != nil { auxiliary = .candidates }
            default: break
            }
            self.request = nil
        }
        .onChange(of: model.isSessionCurrent, initial: true) { _, current in if !current { close() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshReview() } }
        .onChange(of: model.reviewDeliveryGeneration) { _, _ in model.refreshReview() }
        .onChange(of: model.review?.terminalMessage) { _, value in if value != nil { model.refreshReview() } }
        .task(id: model.undoOperation) { await model.expireUndo() }
    }

    @ViewBuilder private func currentControls(_ row: IdentificationHistoryRow) -> some View {
        if model.detail?.row.id == row.id, let review = model.review {
            IdentificationHistoryReviewSection(model: review, cardStyle: true,
                onCommunity: { request = .init(id: row.id, action: .community) },
                onReanalysis: { request = .init(id: row.id, action: .reanalyze) },
                feedback: candidateRendering.feedback)
                .id(ObjectIdentifier(review))
        } else if model.isBusy {
            ProgressView("Loading review actions")
        } else {
            SlideToConfirm(label: "Confirm identification", onConfirm: {
                request = .init(id: row.id, action: .confirm)
            }, feedback: candidateRendering.feedback)
                .disabled(!model.canChangeCardScope).accessibilityIdentifier("HistoryConfirmPrimary")
            SlideToConfirm(label: "Mark as incorrect", onConfirm: {
                request = .init(id: row.id, action: .reject)
            }, feedback: candidateRendering.feedback, color: .red)
                .disabled(!model.canChangeCardScope).accessibilityIdentifier("HistoryReject")
        }
    }

    @ViewBuilder private var status: some View {
        if model.pending {
            Label("Change pending", systemImage: "clock")
            Button("Retry change") { model.start(.retry) }.accessibilityIdentifier("HistoryRetry")
            Text("The current identification stays visible until your change is acknowledged.").font(.caption)
        }
        if let message = model.message { Text(message).font(.callout).accessibilityIdentifier("HistoryMessage") }
        if model.detail?.row.id != model.selected, let review = model.review,
           review.hasUnresolvedRequest || review.canRetrySave {
            Button("Review pending change") { auxiliary = .review }
        }
        if model.isBusy { ProgressView().accessibilityLabel("Loading identification history") }
    }

    @ViewBuilder private func auxiliaryContent(_ destination: Auxiliary) -> some View {
        if destination == .candidates, let candidate = retainedCandidates {
            AnalysisCandidateReviewSheet(model: candidate, rendering: candidateRendering)
        } else {
            NavigationStack {
                List {
                    if destination == .review, let review = model.review {
                        IdentificationHistoryReviewSection(model: review).id(ObjectIdentifier(review))
                    } else if destination == .community, let publication = model.publication {
                        IdentificationPublicationSection(model: publication).id(ObjectIdentifier(publication))
                    } else {
                        Text("This identification changed. Return to History to see the updated card.")
                    }
                }
                .navigationTitle(destination == .review ? "Review identification" : "Ask the community")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { auxiliary = nil } } }
            }
        }
    }

    @ViewBuilder private func navigationContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if isEmbedded { content() } else { NavigationStack { content() } }
    }
    private func close() {
        request = nil; auxiliary = nil; retainedCandidates?.close(); retainedCandidates = nil
        model.close()
        if let onClose { onClose() } else { dismiss() }
    }
}
