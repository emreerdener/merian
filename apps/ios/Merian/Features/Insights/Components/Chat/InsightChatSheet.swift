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

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            composer
        }
        .background(Color(uiColor: .systemBackground))
        .task(id: scanId) {
            await viewModel.loadIfNeeded(scanId: scanId, isProActive: true)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close field chat")

            Text("Field chat")
                .font(.headline)

            Spacer()

            Menu {
                if !viewModel.messages.isEmpty {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteCurrentConversation(scanId: scanId) }
                    } label: {
                        Label("Delete chat", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading || viewModel.isDeleting || viewModel.messages.isEmpty)
            .accessibilityLabel("Field chat options")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else if viewModel.messages.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        ForEach(viewModel.messages) { message in
                            InsightChatBubble(message: message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                guard let lastId = viewModel.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastId, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No messages yet")
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
            if !viewModel.isOffline && !viewModel.isSending {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chips, id: \.self) { chip in
                            Button {
                                Task { await viewModel.send(chip, scanId: scanId) }
                            } label: {
                                Text(chip)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isSending)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask a follow-up", text: Binding(
                    get: { viewModel.draftText },
                    set: { viewModel.setDraftText($0) }
                ), axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                )

                Button {
                    composerFocused = false
                    Task { await viewModel.sendDraft(scanId: scanId) }
                } label: {
                    Image(systemName: viewModel.isSending ? "hourglass" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(viewModel.canSend ? Color.white : Color.secondary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(viewModel.canSend ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send follow-up")
            }
            .padding(.horizontal, 16)

            if let error = viewModel.errorMessage, !viewModel.messages.isEmpty {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }
}

private struct InsightChatBubble: View {
    let message: InsightChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 44) }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isUser ? Color.accentColor.opacity(0.16) : Color(uiColor: .secondarySystemBackground))
                )
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                .textSelection(.enabled)

            if !isUser { Spacer(minLength: 44) }
        }
    }
}
