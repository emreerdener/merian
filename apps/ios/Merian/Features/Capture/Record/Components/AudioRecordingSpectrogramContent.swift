import SwiftUI

struct AudioRecordingSpectrogramContent: View {
    let presentation: AudioRecordingPresentation
    let height: CGFloat
    let viewModel: AudioRecordingViewModel

    var body: some View {
        AudioSpectrogramView(
            columns: presentation.spectrogramColumns,
            layout: presentation.spectrogramLayout
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        }
        .overlay {
            if presentation.isReviewing {
                reviewInteractionLayer
            }
        }
        .overlay(alignment: .bottomLeading) {
            if presentation.isReviewing {
                reviewBoostControl
                    .padding(14)
            }
        }
        .padding(.horizontal, 20)
    }

    private var reviewBoostControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            if presentation.reviewBoost.hasFailed {
                Text("Audio boost unavailable. Playing original.")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
            }
            Button(action: viewModel.toggleReviewBoost) {
                HStack(spacing: 4) {
                    Text(presentation.boostTitle)
                    if presentation.reviewBoost.isEnabled && !presentation.reviewBoost.isPreparing {
                        Image(systemName: "checkmark")
                    } else if !presentation.reviewBoost.isPreparing {
                        Image(systemName: "chevron.right")
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.black.opacity(0.28), in: Capsule())
                .background(.ultraThinMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Boost audio")
            .accessibilityValue(presentation.boostAccessibilityValue)
            .accessibilityHint("Changes preview playback only. AI analysis uses the original recording.")
            .accessibilityIdentifier("capture.audio.boost")
        }
    }

    private var reviewInteractionLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            viewModel.updateScrubbing(
                                locationX: value.location.x,
                                width: proxy.size.width
                            )
                        }
                        .onEnded { _ in
                            viewModel.finishScrubbing()
                        }
                )

            if presentation.showsPlayhead(
                isScrubbing: viewModel.isScrubbing
            ) {
                Rectangle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2)
                    .offset(
                        x: AudioSpectrogramSeekingPolicy.playmarkerLeadingX(
                            progress: presentation.playbackProgress,
                            width: proxy.size.width,
                            markerWidth: 2
                        )
                    )
                    .allowsHitTesting(false)
                    .animation(
                        viewModel.isScrubbing
                            ? nil
                            : .linear(duration: 0.033),
                        value: presentation.playbackProgress
                    )
            }
        }
    }
}
