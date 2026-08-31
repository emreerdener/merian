import SwiftUI

struct InsightChatSheet: View {
    @Bindable var viewModel: InsightChatViewModel
    let scanId: String
    let speciesData: SpeciesData?
    let displayName: String
    let timestamp: Date?
    // swiftlint:disable:next implicit_optional_initialization
    var publicScientificName: String? = nil
    var publicAlternativeNames: [String] = []
    var allowsOwnerActions = true
    let prepareForInitialLoad: (@MainActor () async -> Bool)?
    let onToast: (ToastPayload) -> Void
    let onAppendToFieldNotes: (String, InsightChatFieldNotesAppendKind) -> Void
    let onReviewAlternatives: (() -> Void)?
    let onReanalyzeSpecies: (() -> Void)?
    let onClose: () -> Void

    @FocusState private var composerFocused: Bool
    @State private var pendingFeedbackMessage: InsightChatMessage?
    @State private var isFeatureFeedbackSheetPresented = false
    @State private var isDeleteConversationConfirmationPresented = false
    @State private var isStartingInitialLoad = true
    @State private var didFailInitialPreparation = false

    private var chips: [String] {
        if let speciesData {
            return viewModel.suggestionChips(
                for: speciesData,
                timestamp: timestamp,
                displayName: displayName
            )
        }
        return viewModel.publicPostSuggestionChips(displayName: displayName)
    }

    private var hasVisibleMessages: Bool {
        !viewModel.messages.isEmpty || viewModel.pendingUserMessage != nil
    }

    private var showsEmptyAccentGradient: Bool {
        !hasVisibleMessages && !showsInitialLoadingState && !showsBlockingError
    }

    private var showsInitialLoadingState: Bool {
        (prepareForInitialLoad != nil && isStartingInitialLoad) ||
            viewModel.isCheckingAvailability ||
            (viewModel.isLoading && !hasVisibleMessages)
    }

    private var isSendButtonActive: Bool {
        viewModel.canSend
    }

    private var showsPromptChips: Bool {
        guard hasVisibleMessages || !viewModel.isOffline,
              !showsInitialLoadingState,
              !viewModel.isSending,
              viewModel.pendingUserMessage == nil,
              viewModel.draftText.isEmpty,
              !chips.isEmpty else {
            return false
        }

        return !viewModel.isLoadingPrompts || !viewModel.suggestedPrompts.isEmpty
    }

    private var showsBlockingError: Bool {
        (didFailInitialPreparation ||
            (viewModel.errorMessage != nil && !hasVisibleMessages)) &&
            !showsInitialLoadingState
    }

    private var scientificNames: [String] {
        if let speciesData {
            return [
                speciesData.scientificName,
                speciesData.aiScientificName
            ] + (speciesData.candidates?.map(\.scientificName) ?? [])
                + (speciesData.similarSpecies?.lookalikes ?? [])
        }
        return [publicScientificName].compactMap { $0 } + publicAlternativeNames
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
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !showsBlockingError && showsPromptChips {
                        promptSuggestionsInset
                    }
                }
                // Keep this outermost inset pinned to the keyboard. Prompt updates then
                // consume space above it without changing the composer's placement.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !showsBlockingError && !showsInitialLoadingState {
                        persistentComposer
                    }
                }
        }
        .accessibilityIdentifier("InsightChatSheet")
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
        .alert("Delete conversation?", isPresented: $isDeleteConversationConfirmationPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.deleteCurrentConversation(scanId: scanId)
                    if viewModel.errorMessage == nil {
                        onToast(.success("Field chat deleted"))
                    }
                }
            }
        } message: {
            Text("This permanently removes your private Field chat conversation.")
        }
        .sheet(isPresented: $isFeatureFeedbackSheetPresented) {
            InsightChatFeatureFeedbackSheet(
                onSelectionFeedback: { viewModel.performFeedback(.selection) },
                onSubmit: { sentiment, note in
                    submitFeatureFeedback(sentiment: sentiment, note: note)
                }
            )
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
                    viewModel.performFeedback(.success)
                }
            )
        }
        .task(id: scanId) {
            await prepareAndLoad()
        }
    }

    private var emptyAccentGradient: some View {
        InsightChatEmptyAccentGradient()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        InsightChatToolbarContent(
            displayName: displayName,
            allowsOwnerActions: allowsOwnerActions,
            hasMessages: !viewModel.messages.isEmpty,
            isSummarizingNotes: viewModel.isSummarizingNotes,
            onClose: {
                viewModel.performFeedback(.selection)
                onClose()
            },
            onSummarize: {
                viewModel.performFeedback(.selection)
                trackAction("summarize_to_field_notes", message: nil)
                Task {
                    if await viewModel.summarizeForFieldNotes(scanId: scanId) {
                        onToast(.success("Summary ready to review"))
                    }
                }
            },
            onGiveFeedback: {
                viewModel.performFeedback(.selection)
                isFeatureFeedbackSheetPresented = true
            },
            onDelete: {
                viewModel.performFeedback(.selection)
                isDeleteConversationConfirmationPresented = true
            }
        )
    }

    private var messageList: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if showsInitialLoadingState {
                            ProgressView()
                                .accessibilityLabel("Loading Field chat")
                                .accessibilityIdentifier("InsightChatLoadingIndicator")
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
                                                    onToast(.success("Marked helpful"))
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
                                            viewModel.editFailedMessage(scanId: scanId)
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

            if !allowsOwnerActions {
                Text("This Field chat is private and visible only to you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }

    private var unavailableState: some View {
        ContentUnavailableView {
            Label("Chat unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text(viewModel.errorMessage ?? "Field chat is unavailable right now.")
        } actions: {
            Button("Retry") {
                viewModel.performFeedback(.selection)
                Task { await prepareAndLoad() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @MainActor
    private func prepareAndLoad() async {
        isStartingInitialLoad = true
        didFailInitialPreparation = false
        defer { isStartingInitialLoad = false }

        if let prepareForInitialLoad {
            guard await prepareForInitialLoad() else {
                didFailInitialPreparation = true
                return
            }
        }
        guard !Task.isCancelled else { return }
        await viewModel.loadIfNeeded(scanId: scanId, isProActive: true)
    }

    private var persistentComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let error = viewModel.errorMessage, !viewModel.messages.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if viewModel.isOffline {
                offlineComposerNotice
            } else {
                composerInput
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }

    private var promptSuggestionsInset: some View {
        promptChipsRow
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var promptChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Button {
                        viewModel.performFeedback(.selection)
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
                TextField("Ask Naturebook AI", text: Binding(
                    get: { viewModel.draftText },
                    set: { viewModel.setDraftText($0, scanId: scanId) }
                ), axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .accessibilityIdentifier("InsightChatComposerInput")
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("insight-chat-bottom-anchor", anchor: .bottom)
        }
    }

    private func handleAction(_ action: InsightChatReplyAction, message: InsightChatMessage) {
        viewModel.performFeedback(.selection)
        trackAction(action.rawValue, message: message)

        action.perform(messageText: message.text) { copiedText in
            viewModel.copyText(copiedText)
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
                viewModel.performFeedback(.selection)
                trackAction("review_alternatives_from_identification_concern", message: message)
                action()
            }
        }
        let reanalyzeSpecies = onReanalyzeSpecies.map { action in
            {
                viewModel.performFeedback(.selection)
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
                onToast(.success("Feedback sent"))
            }
        }
    }

    private func trackAction(_ action: String, message: InsightChatMessage?) {
        let hasLookalikes = speciesData.map {
            InsightChatViewModel.hasLookalikeContext($0)
        } ?? !publicAlternativeNames.isEmpty
        viewModel.trackAction(FieldChatActionTelemetry(
            action: action,
            subjectId: scanId,
            messageId: message?.id ?? "",
            isRefusal: message?.isRefusal ?? false,
            hasLookalikes: hasLookalikes
        ))
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
                onToast(.success("Feedback sent"))
            }
        }
    }

    private func trackPromptChip(_ prompt: String) {
        let promptCategory = viewModel.category(forPrompt: prompt)
        let hasLookalikes = speciesData.map {
            InsightChatViewModel.hasLookalikeContext($0)
        } ?? !publicAlternativeNames.isEmpty
        viewModel.trackAction(FieldChatActionTelemetry(
            action: "prompt_chip",
            subjectId: scanId,
            hasLookalikes: hasLookalikes,
            promptCategory: promptCategory
        ))
    }

}
