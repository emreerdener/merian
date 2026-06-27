import SwiftUI

struct InsightChatSheet: View {
    @Bindable var viewModel: InsightChatViewModel
    let scanId: String
    let speciesData: SpeciesData
    let timestamp: Date?
    let onClose: () -> Void

    @FocusState private var composerFocused: Bool

    private var chips: [String] {
        viewModel.suggestionChips(for: speciesData, timestamp: timestamp)
    }

    private var hasVisibleMessages: Bool {
        !viewModel.messages.isEmpty || viewModel.pendingUserMessage != nil
    }

    private var isSendButtonActive: Bool {
        viewModel.canSend || viewModel.isSending
    }

    var body: some View {
        NavigationStack {
            messageList
                .background(Color(uiColor: .systemBackground))
                .navigationTitle("Field chat")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) {
                    composer
                }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
        .task(id: scanId) {
            await viewModel.loadIfNeeded(scanId: scanId, isProActive: true)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
            }
            .accessibilityLabel("Close field chat")
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 2) {
                Text("Field chat")
                    .font(.headline)
                Text(speciesData.commonName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

    }

    private var messageList: some View {
        Group {
            if viewModel.isLoading && !hasVisibleMessages {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !hasVisibleMessages {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                                InsightChatBubble(
                                    message: message,
                                    isLastMessage: index == viewModel.messages.count - 1 && viewModel.pendingUserMessage == nil
                                )
                                .id(message.id)
                            }

                            if let pendingMessage = viewModel.pendingUserMessage {
                                InsightChatPendingUserBubble(message: pendingMessage)
                                    .id(pendingMessage.id)
                                InsightChatAssistantLoadingBubble()
                                    .id("assistant-loading-\(pendingMessage.id)")
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("insight-chat-bottom-anchor")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: viewModel.messages.count) { _, _ in
                        scrollToBottom(proxy)
                    }
                    .onChange(of: viewModel.pendingUserMessage?.id) { _, _ in
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image("sparkle")
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
                .foregroundStyle(.secondary)
            Text("What would you like to know?")
                .font(.headline)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !viewModel.isOffline && !viewModel.isSending && !chips.isEmpty && viewModel.draftText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            Button {
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
                            .disabled(viewModel.isSending)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Merian AI", text: Binding(
                    get: { viewModel.draftText },
                    set: { viewModel.setDraftText($0) }
                ), axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .padding(.vertical, 11)
                .padding(.leading, 16)

                Button {
                    composerFocused = false
                    Task { await viewModel.sendDraft(scanId: scanId) }
                } label: {
                    ZStack {
                        if viewModel.isSending {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(viewModel.canSend ? Color.white : Color.secondary)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(isSendButtonActive ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .accessibilityLabel(viewModel.isSending ? "Sending follow-up" : "Send follow-up")
                .padding(.trailing, 8)
                .padding(.bottom, 6)
            }
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

            if let error = viewModel.errorMessage, !viewModel.messages.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("insight-chat-bottom-anchor", anchor: .bottom)
        }
    }
}

private struct InsightChatBubble: View {
    let message: InsightChatMessage
    let isLastMessage: Bool

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        if isUser {
            HStack {
                Spacer(minLength: 44)

                Text(message.text)
                    .font(.subheadline)
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
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                
                if isLastMessage {
                    Text("Merian AI can make mistakes.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct InsightChatPendingUserBubble: View {
    let message: PendingInsightChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 44)

            Text(message.text)
                .font(.subheadline)
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
