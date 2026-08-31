import SwiftUI

struct InsightChatToolbarContent: ToolbarContent {
    let displayName: String
    let allowsOwnerActions: Bool
    let hasMessages: Bool
    let isSummarizingNotes: Bool
    let onClose: () -> Void
    let onSummarize: () -> Void
    let onGiveFeedback: () -> Void
    let onDelete: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
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
                Text(displayName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        if allowsOwnerActions || hasMessages {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if allowsOwnerActions {
                        Button(action: onSummarize) {
                            Label(
                                isSummarizingNotes ? "Summarizing..." : "Summarize to notes",
                                systemImage: "text.badge.plus"
                            )
                        }
                        .disabled(!hasMessages || isSummarizingNotes)

                        Button(action: onGiveFeedback) {
                            Label("Give feedback", systemImage: "message")
                        }
                    }

                    if hasMessages {
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete conversation", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                }
                .accessibilityLabel("Field chat options")
            }
        }
    }
}
