import SwiftUI

struct ExplorePostDetailSkeleton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isGlowing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 12)

                mediaView
                    .padding(.horizontal, 16)

                actionRow
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                VStack(spacing: 24) {
                    speciesSection
                    insightCardsSection
                    insightCardsSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Circle()
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: 34, height: 34)
            }
        }
        .opacity(isGlowing ? 1.0 : 0.6)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
        .accessibilityHidden(true)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill))
                        .frame(width: 92, height: 17)

                    Capsule()
                        .fill(placeholderFill(secondary: true))
                        .frame(width: 34, height: 16)
                }

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(placeholderFill(secondary: true))
                    .frame(width: 82, height: 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var mediaView: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        placeholderFill(secondary: true),
                        placeholderFill()
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.5)
            }
    }

    private var actionRow: some View {
        HStack(spacing: 20) {
            actionGroup
            actionGroup
            Spacer(minLength: 12)
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 24, height: 24)
        }
    }

    private var actionGroup: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(placeholderFill(secondary: true))
                .frame(width: 24, height: 24)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(placeholderFill())
                .frame(width: 18, height: 14)
        }
    }

    private var speciesSection: some View {
        VStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(placeholderFill(secondary: true))
                .frame(width: 154, height: 20)

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(placeholderFill())
                .frame(width: 248, height: 38)

            VStack(spacing: 8) {
                reasoningLine(width: nil)
                reasoningLine(width: nil)
                reasoningLine(width: 270)
                reasoningLine(width: 208)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func reasoningLine(width: CGFloat?) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(placeholderFill(secondary: true))
            .frame(maxWidth: width == nil ? .infinity : nil)
            .frame(width: width, height: 16)
    }

    private var insightCardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(maxWidth: .infinity)
                .frame(height: 120)
        }
    }

    private func placeholderFill(secondary: Bool = false) -> Color {
        if colorScheme == .dark {
            return secondary
                ? Color(uiColor: .secondarySystemFill)
                : Color(uiColor: .tertiarySystemFill)
        }

        let base = secondary
            ? Color(uiColor: .secondarySystemFill)
            : Color(uiColor: .tertiarySystemFill)
        return base.opacity(isGlowing ? 0.86 : 0.66)
    }
}
