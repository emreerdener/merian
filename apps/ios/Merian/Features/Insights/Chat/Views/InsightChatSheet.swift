import SwiftUI
import UIKit

enum InsightChatFieldNotesAppendKind {
    case summary
}

struct InsightChatSheet: View {
    @Bindable var viewModel: InsightChatViewModel
    let scanId: String
    let speciesData: SpeciesData
    let displayName: String
    let timestamp: Date?
    let onToast: (String) -> Void
    let onAppendToFieldNotes: (String, InsightChatFieldNotesAppendKind) -> Void
    let onReviewAlternatives: (() -> Void)?
    let onReanalyzeSpecies: (() -> Void)?
    let onClose: () -> Void

    @FocusState private var composerFocused: Bool
    @State private var pendingFeedbackMessage: InsightChatMessage?
    @State private var isFeatureFeedbackSheetPresented = false

    private var chips: [String] {
        viewModel.suggestionChips(
            for: speciesData,
            timestamp: timestamp,
            displayName: displayName
        )
    }

    private var hasVisibleMessages: Bool {
        !viewModel.messages.isEmpty || viewModel.pendingUserMessage != nil
    }

    private var showsEmptyAccentGradient: Bool {
        !hasVisibleMessages && !viewModel.isLoading && !showsBlockingError
    }

    private var isSendButtonActive: Bool {
        viewModel.canSend
    }

    private var showsPromptChips: Bool {
        guard hasVisibleMessages || !viewModel.isOffline,
              !viewModel.isLoading,
              !viewModel.isSending,
              viewModel.pendingUserMessage == nil,
              viewModel.draftText.isEmpty,
              !chips.isEmpty else {
            return false
        }

        return !viewModel.isLoadingPrompts || !viewModel.suggestedPrompts.isEmpty
    }

    private var showsBlockingError: Bool {
        viewModel.errorMessage != nil && !hasVisibleMessages && !viewModel.isLoading
    }

    private var scientificNames: [String] {
        [
            speciesData.scientificName,
            speciesData.aiScientificName
        ] + (speciesData.candidates?.map(\.scientificName) ?? [])
            + (speciesData.similarSpecies?.lookalikes ?? [])
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()

                emptyAccentGradient
                    .opacity(showsEmptyAccentGradient ? 1 : 0)
                    .animation(.easeOut(duration: 0.24), value: showsEmptyAccentGradient)

                messageList
            }
                .navigationTitle("Field chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) {
                    if !showsBlockingError {
                        composer
                    }
                }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
        .confirmationDialog(
            "What seems wrong?",
            isPresented: Binding(
                get: { pendingFeedbackMessage != nil },
                set: { if !$0 { pendingFeedbackMessage = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Not helpful") { submitFeedback(.notHelpful) }
            Button("Seems wrong") { submitFeedback(.wrong) }
            Button("Unsafe") { submitFeedback(.unsafe) }
            Button("Other") { submitFeedback(.other) }
            Button("Cancel", role: .cancel) {
                pendingFeedbackMessage = nil
            }
        }
        .sheet(isPresented: $isFeatureFeedbackSheetPresented) {
            InsightChatFeatureFeedbackSheet { sentiment, note in
                submitFeatureFeedback(sentiment: sentiment, note: note)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.notesSummaryDraft != nil },
            set: { if !$0 { viewModel.notesSummaryDraft = nil } }
        )) {
            InsightChatNotesDraftSheet(
                draftText: viewModel.notesSummaryDraft ?? "",
                onCancel: {
                    viewModel.notesSummaryDraft = nil
                },
                onAppend: { draft in
                    onAppendToFieldNotes(draft, .summary)
                    HapticManager.shared.triggerSuccessPulse()
                }
            )
        }
        .task(id: scanId) {
            await viewModel.loadIfNeeded(scanId: scanId, isProActive: true)
        }
    }

    private var emptyAccentGradient: some View {
        InsightChatEmptyAccentGradient()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticManager.shared.triggerSelectionPulse()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
            .accessibilityLabel("Close field chat")
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text("Field chat")
                    .font(.headline)
                Text(displayName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    trackAction("summarize_to_field_notes", message: nil)
                    Task {
                        if await viewModel.summarizeForFieldNotes(scanId: scanId) {
                            onToast("Summary ready to review")
                        }
                    }
                } label: {
                    Label(
                        viewModel.isSummarizingNotes ? "Summarizing..." : "Summarize to notes",
                        systemImage: "text.badge.plus"
                    )
                }
                .disabled(viewModel.messages.isEmpty || viewModel.isSummarizingNotes)

                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    isFeatureFeedbackSheetPresented = true
                } label: {
                    Label("Give feedback", systemImage: "message")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
            }
            .accessibilityLabel("Field chat options")
        }
    }

    private var messageList: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if viewModel.isLoading && !hasVisibleMessages {
                            ProgressView()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else if showsBlockingError {
                            unavailableState
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else if !hasVisibleMessages {
                            emptyState
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                                    InsightChatBubble(
                                        message: message,
                                        scientificNames: scientificNames,
                                        isLastMessage: index == viewModel.messages.count - 1 && viewModel.pendingUserMessage == nil,
                                        feedbackRating: viewModel.submittedFeedback[message.id],
                                        identificationReviewActions: identificationReviewActions(
                                            for: message,
                                            at: index
                                        ),
                                        onAction: { action in
                                            handleAction(action, message: message)
                                        },
                                        onPositiveFeedback: {
                                            Task {
                                                let didSubmit = await viewModel.submitFeedback(
                                                    scanId: scanId,
                                                    messageId: message.id,
                                                    rating: .helpful
                                                )
                                                if didSubmit {
                                                    onToast("Marked helpful")
                                                }
                                            }
                                        },
                                        onNegativeFeedback: {
                                            pendingFeedbackMessage = message
                                        }
                                    )
                                    .id(message.id)
                                }

                                if let pendingMessage = viewModel.pendingUserMessage {
                                    InsightChatPendingUserBubble(
                                        message: pendingMessage,
                                        scientificNames: scientificNames,
                                        onRetry: {
                                            Task { await viewModel.retryFailedMessage(scanId: scanId) }
                                        },
                                        onEdit: {
                                            viewModel.editFailedMessage()
                                            composerFocused = true
                                        }
                                    )
                                        .id(pendingMessage.id)
                                    if pendingMessage.isSending {
                                        InsightChatAssistantLoadingBubble()
                                            .id("assistant-loading-\(pendingMessage.id)")
                                    }
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("insight-chat-bottom-anchor")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .background(
                    ExploreKeyboardDismissTapRecognizer(
                        isEnabled: composerFocused,
                        onTap: { composerFocused = false }
                    )
                )
                .onChange(of: viewModel.messages.count) { _, _ in
                    scrollToBottom(proxy)
                }
                .onChange(of: viewModel.pendingUserMessage?.id) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("sparkles")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
            Text("What would you like to know about \(displayName)?")
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("Chat unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(viewModel.errorMessage ?? "Field chat is unavailable right now.")
        } actions: {
            Button("Retry") {
                HapticManager.shared.triggerSelectionPulse()
                Task { await viewModel.load(scanId: scanId) }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsPromptChips {
                promptChipsRow
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
            }

            if viewModel.isOffline {
                offlineComposerNotice
            } else {
                composerInput
            }

            if let error = viewModel.errorMessage, !viewModel.messages.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.24), value: showsPromptChips)
    }

    private var promptChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        HapticManager.shared.triggerSelectionPulse()
                        trackPromptChip(chip)
                        Task { await viewModel.send(chip, scanId: scanId) }
                    } label: {
                        Text(chip)
                            .lineLimit(1)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
                            )
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSending || viewModel.isOffline)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var offlineComposerNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
            Text("Connect to ask a follow-up.")
                .font(.subheadline)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var composerInput: some View {
        HStack(alignment: .center, spacing: 10) {
                TextField("Ask Merian AI", text: Binding(
                    get: { viewModel.draftText },
                    set: { viewModel.setDraftText($0) }
                ), axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .padding(.vertical, 6)
                .padding(.leading, 16)

                Button {
                    composerFocused = false
                    Task { await viewModel.sendDraft(scanId: scanId) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(viewModel.canSend ? Color.white : Color.secondary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isSendButtonActive ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send follow-up")
                .padding(.trailing, 8)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("insight-chat-bottom-anchor", anchor: .bottom)
        }
    }

    private func handleAction(_ action: InsightChatReplyAction, message: InsightChatMessage) {
        HapticManager.shared.triggerSelectionPulse()
        trackAction(action.rawValue, message: message)

        switch action {
        case .copyAnswer:
            UIPasteboard.general.string = message.text
            onToast("Copied answer")
        }
    }

    private func identificationReviewActions(
        for message: InsightChatMessage,
        at index: Int
    ) -> InsightChatIdentificationReviewActions? {
        guard viewModel.shouldOfferIdentificationReviewActions(forAssistantMessageAt: index) else {
            return nil
        }

        let reviewAlternatives = onReviewAlternatives.map { action in
            {
                HapticManager.shared.triggerSelectionPulse()
                trackAction("review_alternatives_from_identification_concern", message: message)
                action()
            }
        }
        let reanalyzeSpecies = onReanalyzeSpecies.map { action in
            {
                HapticManager.shared.triggerSelectionPulse()
                trackAction("reanalyze_species_from_identification_concern", message: message)
                action()
            }
        }

        guard reviewAlternatives != nil || reanalyzeSpecies != nil else { return nil }
        return InsightChatIdentificationReviewActions(
            onReviewAlternatives: reviewAlternatives,
            onReanalyzeSpecies: reanalyzeSpecies
        )
    }

    private func submitFeedback(_ rating: InsightChatFeedbackRating) {
        guard let message = pendingFeedbackMessage else { return }
        pendingFeedbackMessage = nil
        trackAction("feedback_\(rating.rawValue)", message: message)
        Task {
            let didSubmit = await viewModel.submitFeedback(
                scanId: scanId,
                messageId: message.id,
                rating: rating
            )
            if didSubmit {
                onToast("Feedback sent")
            }
        }
    }

    private func trackAction(_ action: String, message: InsightChatMessage?) {
        PostHogManager.shared.capture("InsightChatActionTapped", properties: [
            "action": action,
            "scan_id": scanId,
            "message_id": message?.id ?? "",
            "is_refusal": message?.isRefusal ?? false,
            "has_lookalikes": InsightChatViewModel.hasLookalikeContext(speciesData)
        ])
    }

    private func submitFeatureFeedback(
        sentiment: InsightChatFeatureFeedbackSentiment?,
        note: String
    ) {
        Task {
            let didSubmit = await viewModel.submitFeatureFeedback(
                scanId: scanId,
                sentiment: sentiment,
                note: note
            )
            if didSubmit {
                onToast("Feedback sent")
            }
        }
    }

    private func trackPromptChip(_ prompt: String) {
        PostHogManager.shared.capture("InsightChatActionTapped", properties: [
            "action": "prompt_chip",
            "prompt_category": viewModel.category(forPrompt: prompt),
            "scan_id": scanId,
            "message_id": "",
            "is_refusal": false,
            "has_lookalikes": InsightChatViewModel.hasLookalikeContext(speciesData)
        ])
    }
}

private enum InsightChatReplyAction: String, CaseIterable {
    case copyAnswer = "copy_answer"
}

private struct InsightChatIdentificationReviewActions {
    let onReviewAlternatives: (() -> Void)?
    let onReanalyzeSpecies: (() -> Void)?
}

private struct InsightChatBubble: View {
    let message: InsightChatMessage
    let scientificNames: [String]
    let isLastMessage: Bool
    let feedbackRating: InsightChatFeedbackRating?
    let identificationReviewActions: InsightChatIdentificationReviewActions?
    let onAction: (InsightChatReplyAction) -> Void
    let onPositiveFeedback: () -> Void
    let onNegativeFeedback: () -> Void

    private var isUser: Bool {
        message.role == .user
    }

    private var formattedText: AttributedString {
        InsightChatMessageFormatter.formattedText(
            message.text,
            scientificNames: scientificNames
        )
    }

    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 44)

                Text(formattedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if message.isRefusal {
                    Label("Safe field guidance", systemImage: "shield.lefthalf.filled")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(formattedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if let identificationReviewActions {
                    InsightChatIdentificationReviewPanel(actions: identificationReviewActions)
                        .padding(.top, 4)
                }

                InsightChatAnswerControls(
                    feedbackRating: feedbackRating,
                    onPositiveFeedback: onPositiveFeedback,
                    onNegativeFeedback: onNegativeFeedback,
                    onCopy: {
                        onAction(.copyAnswer)
                    }
                )

                if isLastMessage {
                    Text("Merian AI can make mistakes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

}

private struct InsightChatIdentificationReviewPanel: View {
    let actions: InsightChatIdentificationReviewActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Review identification", systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text("Compare the saved alternatives or add more evidence for a fresh pass.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let onReviewAlternatives = actions.onReviewAlternatives {
                    actionButton(
                        title: "Review alternatives",
                        systemImage: "person.fill.checkmark.and.xmark",
                        action: onReviewAlternatives
                    )
                }

                if let onReanalyzeSpecies = actions.onReanalyzeSpecies {
                    actionButton(
                        title: "Reanalyze species",
                        systemImage: "arrow.2.circlepath",
                        action: onReanalyzeSpecies
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    }

    private func actionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(uiColor: .systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

private struct InsightChatPendingUserBubble: View {
    let message: PendingInsightChatMessage
    let scientificNames: [String]
    let onRetry: () -> Void
    let onEdit: () -> Void

    private var formattedText: AttributedString {
        InsightChatMessageFormatter.formattedText(
            message.text,
            scientificNames: scientificNames
        )
    }

    var body: some View {
        HStack {
            Spacer(minLength: 44)

            VStack(alignment: .trailing, spacing: 6) {
                Text(formattedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    )
                    .textSelection(.enabled)

                if case .failed(let reason) = message.deliveryState {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Edit", action: onEdit)
                            Button("Try again", action: onRetry)
                                .fontWeight(.semibold)
                        }
                        .font(.caption)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

private struct InsightChatAnswerControls: View {
    let feedbackRating: InsightChatFeedbackRating?
    let onPositiveFeedback: () -> Void
    let onNegativeFeedback: () -> Void
    let onCopy: () -> Void

    @State private var copyConfirmationToken: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                copyControl

                feedbackControls
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
    }

    private var copyControl: some View {
        HStack(spacing: 8) {
            Button {
                showCopyConfirmation()
                onCopy()
            } label: {
                Image(systemName: "square.on.square")
            }
            .accessibilityLabel("Copy answer")

            if copyConfirmationToken != nil {
                Text("Copied")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var feedbackControls: some View {
        if let feedbackRating {
            Label(feedbackRating == .helpful ? "Helpful" : "Feedback sent", systemImage: "checkmark.circle")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        } else {
            HStack(spacing: 14) {
                Button(action: onPositiveFeedback) {
                    Image(systemName: "hand.thumbsup")
                }
                .accessibilityLabel("Mark answer helpful")

                Button(action: onNegativeFeedback) {
                    Image(systemName: "hand.thumbsdown")
                }
                .accessibilityLabel("Report answer")
            }
        }
    }

    private func showCopyConfirmation() {
        let token = UUID()
        withAnimation(.easeOut(duration: 0.16)) {
            copyConfirmationToken = token
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard copyConfirmationToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                copyConfirmationToken = nil
            }
        }
    }
}

private struct InsightChatFeatureFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textIsFocused: Bool
    @State private var selectedSentiment: InsightChatFeatureFeedbackSentiment?
    @State private var feedbackText = ""

    let onSubmit: (InsightChatFeatureFeedbackSentiment?, String) -> Void

    private var trimmedFeedbackText: String {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        selectedSentiment != nil || !trimmedFeedbackText.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("How is Field chat working?")
                    .font(.title3.weight(.semibold))

                sentimentPicker

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $feedbackText)
                        .focused($textIsFocused)
                        .frame(minHeight: 150)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                        )

                    if feedbackText.isEmpty {
                        Text("Tell us what felt good, confusing, wrong, or missing.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 20)
                            .allowsHitTesting(false)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .navigationTitle("Give feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        onSubmit(selectedSentiment, trimmedFeedbackText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
            .onAppear {
                textIsFocused = true
            }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
    }

    private var sentimentPicker: some View {
        HStack(spacing: 10) {
            ForEach(InsightChatFeatureFeedbackSentiment.allCases, id: \.self) { sentiment in
                Button {
                    HapticManager.shared.triggerSelectionPulse()
                    selectedSentiment = sentiment
                } label: {
                    Label(sentiment.title, systemImage: sentiment.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(sentiment == selectedSentiment
                                      ? Color.accentColor.opacity(0.16)
                                      : Color(uiColor: .secondarySystemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    sentiment == selectedSentiment
                                        ? Color.accentColor.opacity(0.45)
                                        : Color.primary.opacity(0.08),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(sentiment == selectedSentiment ? Color.accentColor : Color.primary)
            }
        }
    }
}

private struct InsightChatNotesDraftSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draftText: String
    @State private var confirmationMessage: String?
    @State private var isCompletingAppend = false
    let onCancel: () -> Void
    let onAppend: (String) -> Void

    init(draftText: String, onCancel: @escaping () -> Void, onAppend: @escaping (String) -> Void) {
        _draftText = State(initialValue: draftText)
        self.onCancel = onCancel
        self.onAppend = onAppend
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $draftText)
                .padding()
                .navigationTitle("Review note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            onCancel()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .accessibilityLabel("Close note review")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        appendAndConfirm()
                    } label: {
                        Label("Add to field notes", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCompletingAppend)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.bar)
                }
        }
        .overlay(alignment: .bottom) {
            if let confirmationMessage {
                ToastBanner(onDismiss: nil) {
                    Label(confirmationMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.bottom, 104)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: confirmationMessage)
    }

    private func appendAndConfirm() {
        guard !isCompletingAppend else { return }
        let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isCompletingAppend = true
        onAppend(draftText)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            confirmationMessage = "Added to field notes"
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeOut(duration: 0.18)) {
                confirmationMessage = nil
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            onCancel()
            dismiss()
        }
    }
}

private struct InsightChatEmptyAccentGradient: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hueRotationDegrees = 0.0

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(red: 0.28, green: 0.68, blue: 1.0).opacity(0.28), location: 0),
                .init(color: Color(red: 0.44, green: 0.78, blue: 1.0).opacity(0.16), location: 0.24),
                .init(color: Color(red: 0.64, green: 0.48, blue: 1.0).opacity(0.07), location: 0.5),
                .init(color: Color(red: 0.28, green: 0.68, blue: 1.0).opacity(0), location: 0.74)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .hueRotation(.degrees(reduceMotion ? 0 : hueRotationDegrees))
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }

            withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                hueRotationDegrees = 360
            }
        }
        .onChange(of: reduceMotion) { _, isReduced in
            if isReduced {
                hueRotationDegrees = 0
            } else {
                withAnimation(.linear(duration: 28).repeatForever(autoreverses: false)) {
                    hueRotationDegrees = 360
                }
            }
        }
    }
}

private enum InsightChatMessageFormatter {
    static func formattedText(_ text: String, scientificNames: [String]) -> AttributedString {
        let cleaned = textByRemovingScientificNameMarkers(from: text)
        var result = AttributedString(cleaned.text)

        for scientificName in uniqueNames(scientificNames + cleaned.markedScientificNames) {
            applyMonospacedStyle(to: &result, matching: scientificName)
        }

        return result
    }

    private static func textByRemovingScientificNameMarkers(
        from text: String
    ) -> (text: String, markedScientificNames: [String]) {
        var output = ""
        var markedScientificNames: [String] = []
        var cursor = text.startIndex

        while let opening = text[cursor...].firstIndex(of: "*") {
            let afterOpening = text.index(after: opening)
            guard let closing = text[afterOpening...].firstIndex(of: "*") else { break }

            let candidate = String(text[afterOpening..<closing])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            output += String(text[cursor..<opening])
            if isLikelyScientificName(candidate) {
                output += candidate
                markedScientificNames.append(candidate)
            } else {
                output += "*" + candidate + "*"
            }

            cursor = text.index(after: closing)
        }

        output += String(text[cursor...])
        return (output, markedScientificNames)
    }

    private static func isLikelyScientificName(_ text: String) -> Bool {
        let words = text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard (2...4).contains(words.count),
              let firstCharacter = words.first?.first,
              firstCharacter.isUppercase else {
            return false
        }

        return words.dropFirst().allSatisfy { word in
            let trimmed = word.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}"))
            guard let firstCharacter = trimmed.first else { return false }
            return firstCharacter.isLowercase || firstCharacter == "x" || firstCharacter == "×"
        }
    }

    private static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    private static func applyMonospacedStyle(to text: inout AttributedString, matching scientificName: String) {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text[searchRange].range(of: scientificName, options: .caseInsensitive) {
            text[range].font = .system(.body, design: .monospaced)
            searchRange = range.upperBound..<text.endIndex
        }
    }
}

private struct InsightChatAssistantLoadingBubble: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
            Text("Thinking")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Field chat is thinking")
    }
}
