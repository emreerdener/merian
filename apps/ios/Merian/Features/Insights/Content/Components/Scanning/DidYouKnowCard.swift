import SwiftUI

/// A rotating curiosity card shown during inference to give users something to read while waiting.
/// Resumes a persisted shuffled deck, auto-advances every 8.5 seconds, and
/// responds to taps for manual advance.
struct DidYouKnowCard: View {
    @StateObject private var factManager: FactManager
    let onSelectionFeedback: () -> Void

    init(
        factManager: FactManager,
        onSelectionFeedback: @escaping () -> Void = {}
    ) {
        _factManager = StateObject(wrappedValue: factManager)
        self.onSelectionFeedback = onSelectionFeedback
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            MerianCardHeader(systemImage: "info.circle", title: "Did you know?")

            // Rotating fact
            ZStack(alignment: .topLeading) {
                // Invisible max-height anchor so the card doesn't jump when facts differ in length.
                // Uses the longest fact to size the reserved area.
                Text(FactLibrary.longestFact)
                    .font(.system(.body))
                    .opacity(0)
                    .fixedSize(horizontal: false, vertical: true)

                Text(factManager.currentFact.text)
                    .font(.system(.body))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(factManager.currentIndex)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: factManager.currentIndex)
            }

            // Footer: Pagination and Category
            HStack {
                // Dot pagination — 5-dot rolling window
                HStack(spacing: 6) {
                    let windowStart = (factManager.currentIndex / 5) * 5
                    ForEach(0..<min(5, FactLibrary.facts.count - windowStart), id: \.self) { offset in
                        Circle()
                            .fill(offset == factManager.currentIndex % 5
                                  ? Color.primary.opacity(0.6)
                                  : Color.secondary.opacity(0.25))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.25), value: factManager.currentIndex)
                    }
                }

                Spacer()

                Text("#\(factManager.currentFact.category)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
                    .tracking(1)
                    .foregroundStyle(.secondary)
                    .id(factManager.currentIndex)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: factManager.currentIndex)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    // Horizontal swipe to change facts
                    if value.translation.width < -20 {
                        advance()
                    } else if value.translation.width > 20 {
                        retreat()
                    }
                }
        )
        .task(id: factManager.currentIndex) {
            // Defer decoding and deck preparation until the first layout has
            // completed.
            await factManager.prepareIfNeeded()

            // Modern iOS clock API prevents runaway ms loops
            try? await Task.sleep(for: .seconds(8.5))
            guard !Task.isCancelled else { return }

            advance()
        }
    }

    private func advance() {
        onSelectionFeedback()
        withAnimation(.easeInOut(duration: 0.35)) {
            factManager.advance()
        }
    }

    private func retreat() {
        onSelectionFeedback()
        withAnimation(.easeInOut(duration: 0.35)) {
            factManager.retreat()
        }
    }
}
