import SwiftUI

/// Curated highlights for the upcoming build, separate from the full changelog.
struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showsChangelog = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What’s new")
                            .font(.largeTitle.bold())
                            .accessibilityIdentifier("WhatsNew_Title")
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 32) {
                        // Reserved for the next release; omit from this announcement.
                        // highlight(
                        //     symbol: "viewfinder",
                        //     title: "Scan status at a glance",
                        //     detail: "Queue scans and keep discovering. Follow their progress with the new activity indicator and get notified when identifications are ready."
                        // )

                        highlight(
                            symbol: "map",
                            title: "Improved maps",
                            detail: "Explore maps with terrain view by default, location search, improved zoom controls, and a distance scale."
                        )

                        highlight(
                            symbol: "text.bubble",
                            title: "More context, better results",
                            detail: "Add a description to help improve identification accuracy. Available to everyone."
                        )

                        highlight(
                            symbol: "face.smiling",
                            title: "React with emojis",
                            detail: "Add emoji reactions to Explore posts to celebrate discoveries and share how you feel."
                        )

                        highlight(
                            symbol: "clock.arrow.circlepath",
                            title: "Identification history",
                            detail: "Review past identifications and switch back to an earlier result after reanalysis."
                        )

                        highlight(
                            symbol: "speaker.wave.2",
                            title: "Boost audio",
                            detail: "Make quiet bird calls and other sounds easier to hear when listening to your recordings."
                        )

                        highlight(
                            symbol: "xmark.circle",
                            title: "Mark as incorrect",
                            detail: "Flag an AI identification when you know it doesn’t match what you found."
                        )
                    }

                    VStack(spacing: 24) {
                        Button {
                            showsChangelog = true
                        } label: {
                            Text("View more")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("WhatsNew_ViewMore")
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)

                        Button {
                            dismiss()
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("WhatsNew_Continue")
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .accessibilityIdentifier("WhatsNew_Content")
            .navigationDestination(isPresented: $showsChangelog) {
                ChangelogView()
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
