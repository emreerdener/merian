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

    private var showsEmptyAccentGradient: Bool {
        !hasVisibleMessages && !viewModel.isLoading && !showsBlockingError
    }

    private var isSendButtonActive: Bool {
        viewModel.canSend || viewModel.isSending
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
        .task(id: scanId) {
            await viewModel.loadIfNeeded(scanId: scanId, isProActive: true)
        }
    }

    private var emptyAccentGradient: some View {
        LinearGradient(
            stops: [
                .init(color: Color.accentColor.opacity(0.24), location: 0),
                .init(color: Color.accentColor.opacity(0.13), location: 0.24),
                .init(color: Color.accentColor.opacity(0.04), location: 0.48),
                .init(color: Color.accentColor.opacity(0), location: 0.7)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
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
                Text(speciesData.commonName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
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
                                        isLastMessage: index == viewModel.messages.count - 1 && viewModel.pendingUserMessage == nil
                                    )
                                    .id(message.id)
                                }

                                if let pendingMessage = viewModel.pendingUserMessage {
                                    InsightChatPendingUserBubble(
                                        message: pendingMessage,
                                        scientificNames: scientificNames
                                    )
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
            Text("What would you like to know about \(speciesData.commonName)?")
                .font(.title2)
                .multilineTextAlignment(.center)
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
    let scientificNames: [String]
    let isLastMessage: Bool

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
                Text(formattedText)
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
    let scientificNames: [String]

    private var formattedText: AttributedString {
        InsightChatMessageFormatter.formattedText(
            message.text,
            scientificNames: scientificNames
        )
    }

    var body: some View {
        HStack {
            Spacer(minLength: 44)

            Text(formattedText)
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
            text[range].font = .system(.subheadline, design: .monospaced)
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
