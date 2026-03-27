import SwiftUI
import SwiftData
import RevenueCat

struct PremiumInsightsCard: View {
    let habitatDescription: String?
    let globalDistributionRegions: [String]?
    let scientificName: String?
    let scanId: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine

    @State private var isUnlocking = false
    @State private var unlockError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
                    .frame(width: 28, height: 28)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(Circle())

                Text("Premium Insights")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal)

            if let habitat = habitatDescription {
                // UNLOCKED STATE
                VStack(alignment: .leading, spacing: 12) {
                    Text("Habitat & Distribution")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(habitat)
                        .font(.body)
                        .lineSpacing(4)

                    if let regions = globalDistributionRegions, !regions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(regions, id: \.self) { region in
                                    Text(region)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

            } else if inferenceEngine.isPremiumLoading {
                // LOADING STATE
                VStack(alignment: .leading, spacing: 12) {
                    Text("Habitat & Distribution")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(uiColor: .systemFill))
                                .frame(maxWidth: .infinity)
                                .frame(height: 14)
                        }
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(uiColor: .systemFill))
                            .frame(width: 160, height: 14)
                    }
                    .redacted(reason: .placeholder)
                    .shimmering()

                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 72, height: 28)
                        }
                    }
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)

            } else {
                // PAYWALL / RETRY STATE
                VStack(spacing: 16) {
                    if RevenueCatManager.shared.isProActive {
                        Text("Habitat and distribution data couldn't be loaded. Tap to retry.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    } else {
                        Text("Unlock deep ecology insights and global distribution data.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }

                    if let error = unlockError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(action: {
                        if RevenueCatManager.shared.isProActive {
                            Task { await triggerEnrichment() }
                        } else {
                            AppDIContainer.shared.appEventPublisher.send(.triggerPaywall)
                        }
                    }) {
                        HStack {
                            if isUnlocking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(RevenueCatManager.shared.isProActive ? "Retry" : "Unlock Premium Insights")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .clipShape(Capsule())
                    }
                    .disabled(isUnlocking)
                }
                .padding(.vertical, 24)
                .padding(.horizontal)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                .padding(.horizontal)
            }
        }
    }

    @MainActor
    private func triggerEnrichment() async {
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }

        await inferenceEngine.fetchAndApplyEnrichment(modelContext: modelContext)
        HapticManager.shared.triggerSuccessPulse()
    }
}

// MARK: - Shimmer Modifier

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.white.opacity(0.35), location: 0.5),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: geo.size.width * phase)
                .onAppear {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1.5
                    }
                }
            }
            .clipped()
        )
        .clipped()
    }
}

private extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}
