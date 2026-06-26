import SwiftUI

struct InsightChatCard: View {
    @Bindable var viewModel: InsightChatViewModel
    let scanId: String
    let speciesData: SpeciesData
    let timestamp: Date?
    let isProActive: Bool
    let onUnlock: () -> Void

    @FocusState private var composerFocused: Bool

    private var chips: [String] {
        viewModel.suggestionChips(for: speciesData, timestamp: timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InsightCardHeader(systemImage: "sparkles", title: "Field chat") {
                Spacer()
                if isProActive, !viewModel.messages.isEmpty {
                    Button {
                        Task { await viewModel.deleteConversation(scanId: scanId) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isDeleting)
                    .accessibilityLabel("Delete field chat")
                }
            }

            if isProActive {
                proContent
            } else {
                lockedContent
            }
        }
        .card()
        .task(id: "\(scanId)-\(isProActive)") {
            await viewModel.loadIfNeeded(scanId: scanId, isProActive: isProActive)
        }
    }

    @ViewBuilder
    private var proContent: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 72)
        } else {
            if !viewModel.messages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.messages.suffix(6)) { message in
                        InsightChatBubble(message: message)
                    }
                }
            }

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
                        .disabled(viewModel.isSending || viewModel.isOffline)
                    }
                }
                .padding(.vertical, 2)
            }

            composer

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask a follow-up", text: Binding(
                get: { viewModel.draftText },
                set: { viewModel.setDraftText($0) }
            ), axis: .vertical)
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .focused($composerFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )

            Button {
                composerFocused = false
                Task { await viewModel.sendDraft(scanId: scanId) }
            } label: {
                Image(systemName: viewModel.isSending ? "hourglass" : "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(viewModel.canSend ? Color.white : Color.secondary)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(viewModel.canSend ? Color.accentColor : Color(uiColor: .tertiarySystemFill))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Send follow-up")
        }
    }

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask saved follow-up questions with Merian Pro.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onUnlock) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                    Text("Unlock Pro")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.primary, in: Capsule())
                .foregroundStyle(Color(uiColor: .systemBackground))
            }
            .buttonStyle(.plain)
        }
    }
}

private struct InsightChatBubble: View {
    let message: InsightChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 36) }

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

            if !isUser { Spacer(minLength: 36) }
        }
    }
}
