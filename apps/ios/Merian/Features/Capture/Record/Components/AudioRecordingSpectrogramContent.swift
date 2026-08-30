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
        .padding(.horizontal, 20)
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
