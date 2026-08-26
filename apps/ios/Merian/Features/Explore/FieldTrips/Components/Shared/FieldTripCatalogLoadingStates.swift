import SwiftUI

struct FieldTripUnavailableCard: View {
    let title: String
    let message: String
    let retry: () -> Void

    var body: some View {
        EmptyStateView(
            imageName: "fieldtrip-backpack",
            imageHeight: 300,
            title: title,
            message: message
        ) {
            Button("Retry", action: retry)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
    }
}

struct FieldTripTemplateSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: FieldTripScanPreviewLayout.spacing) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(
                        cornerRadius: FieldTripScanPreviewLayout.cornerRadius,
                        style: .continuous
                    )
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.horizontal, FieldTripScanPreviewLayout.horizontalInset)
            .padding(.top, 24)
            .padding(.bottom, 16)

            VStack(alignment: .center, spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(maxWidth: 220)
                    .frame(height: 34)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 15)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(maxWidth: 190)
                    .frame(height: 15)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(
                cornerRadius: FieldTripTemplateCardLayout.cornerRadius,
                style: .continuous
            )
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        }
        .padding(.horizontal, FieldTripTemplateCardLayout.outerHorizontalInset)
        .redacted(reason: .placeholder)
    }
}

struct FieldTripChallengeSkeletonCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(1.3, contentMode: .fit)

                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 64, height: 25)
                    .padding(14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.16))
                            .frame(width: 180, height: 20)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(maxWidth: .infinity)
                            .frame(height: 14)

                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                            .frame(width: 132, height: 11)
                    }

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.16))
                        .frame(width: 8, height: 22)
                }

                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 48, height: 18)
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 58, height: 18)
                }

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 156, height: 11)

                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 82, height: 11)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 96, height: 11)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .redacted(reason: .placeholder)
    }
}

struct FieldTripRecentSkeletonCard: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.16))
                    .frame(width: 160, height: 16)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 110, height: 11)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 90, height: 11)

                HStack(spacing: 6) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 48, height: 18)
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 58, height: 18)
                }

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(width: 138, height: 9)
            }

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 7, height: 13)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .redacted(reason: .placeholder)
    }
}
