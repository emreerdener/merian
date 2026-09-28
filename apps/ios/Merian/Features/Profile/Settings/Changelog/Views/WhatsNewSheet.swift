import SwiftUI

/// Curated highlights for the upcoming build, separate from the full changelog.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What’s new in\nNaturebook")
                            .font(.largeTitle.bold())
                            .accessibilityIdentifier("WhatsNew_Title")
                            .accessibilityAddTraits(.isHeader)

                        Text("Less waiting. More discovering.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 32) {
                        highlight(
                            symbol: "sparkles",
                            title: "2.2× faster AI identifications",
                            detail: "Get to know what you’ve found sooner, with less time waiting for results."
                        )

                        highlight(
                            symbol: "magnifyingglass",
                            title: "Find places on the map",
                            detail: "Search for a location and jump straight to it in your Scans and Explore maps."
                        )

                        highlight(
                            symbol: "text.bubble",
                            title: "More context, better results",
                            detail: "Add a description with details like size, habitat, or behavior to help improve identification accuracy. Available to everyone."
                        )

                        highlight(
                            symbol: "face.smiling",
                            title: "React with emojis",
                            detail: "Add emoji reactions to Explore posts to celebrate discoveries and share how you feel."
                        )

                        highlight(
                            symbol: "speaker.wave.2",
                            title: "Boost quiet recordings",
                            detail: "Make quiet bird calls and other sounds easier to hear when reviewing your recordings."
                        )
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .accessibilityIdentifier("WhatsNew_Continue")
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .frame(maxWidth: 560)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.background)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("WhatsNew_Close")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func highlight(
        symbol: String,
        title: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WhatsNewSheet()
}
