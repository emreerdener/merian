import SwiftUI

/// A system-anchored popover keeps review labels and symbols equally legible
/// in their semantic colors. Actions remain owned by the History model.
struct IdentificationHistoryCardMenu: View {
    let row: IdentificationHistoryRow
    let isCurrent: Bool
    let actionsEnabled: Bool
    let action: (IdentificationHistoryViewModel.CardAction) -> Void
    var onViewReanalysisProgress: (() -> Void)?
    var onViewCommunityRequest: (() -> Void)?
    @State private var isPresented = false
    @State private var pending: Choice?

    private enum Choice {
        case card(IdentificationHistoryViewModel.CardAction)
        case progress, communityRequest
    }

    var body: some View {
        Button { isPresented = true } label: {
            Image(systemName: "ellipsis").foregroundStyle(.primary)
                .frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!actionsEnabled)
        .accessibilityLabel("Actions for \(row.title)")
        .accessibilityIdentifier("HistoryActions_\(row.id.uuidString.lowercased())")
        .popover(isPresented: $isPresented) {
            content
                .presentationCompactAdaptation(.popover)
                .presentationBackground(.regularMaterial)
                .onDisappear { finishDismissal() }
        }
        .onChange(of: actionsEnabled) { _, enabled in
            if !enabled { pending = nil; isPresented = false }
        }
        .onChange(of: isCurrent) { _, _ in pending = nil; isPresented = false }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if !isCurrent {
                HStack(spacing: 8) {
                    reviewButton("Correct", symbol: "checkmark.circle.fill", color: .green,
                        choice: .confirm, identifier: "HistoryCorrectMenu")
                    reviewButton("Incorrect", symbol: "xmark.circle.fill", color: .red,
                        choice: .reject, identifier: "HistoryIncorrectMenu")
                }
                Divider().padding(.vertical, 8)
                menuButton("Use identification", symbol: "checkmark.rectangle.portrait", choice: .card(.use))
                    .accessibilityIdentifier("HistoryRestore")
            }
            if onViewCommunityRequest != nil {
                menuButton("View community request", symbol: "person.2", choice: .communityRequest)
            } else {
                menuButton("Ask the community", symbol: "person.2", choice: .card(.community))
                    .accessibilityIdentifier("HistoryAskCommunity")
            }
            if onViewReanalysisProgress != nil {
                menuButton("View reanalysis progress", symbol: "clock", choice: .progress)
            } else {
                menuButton("Reanalyze", symbol: "arrow.2.circlepath", choice: .card(.reanalyze))
                    .accessibilityIdentifier("HistoryReanalyze")
            }
        }
        .buttonStyle(.plain)
        .disabled(!actionsEnabled)
        .padding(12)
        .frame(width: 280)
    }

    private func reviewButton(_ title: String, symbol: String, color: Color,
                              choice: IdentificationHistoryViewModel.CardAction, identifier: String) -> some View {
        Button { choose(.card(choice)) } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.title2)
                Text(title).font(.subheadline.weight(.medium))
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }

    private func menuButton(_ title: String, symbol: String, choice: Choice) -> some View {
        Button { choose(choice) } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 24)
                Text(title).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.primary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private func choose(_ choice: Choice) {
        guard actionsEnabled else { return }
        pending = choice; isPresented = false
    }

    private func finishDismissal() {
        let choice = pending; pending = nil
        guard actionsEnabled, let choice else { return }
        switch choice {
        case .card(let command): action(command)
        case .progress: onViewReanalysisProgress?()
        case .communityRequest: onViewCommunityRequest?()
        }
    }
}
