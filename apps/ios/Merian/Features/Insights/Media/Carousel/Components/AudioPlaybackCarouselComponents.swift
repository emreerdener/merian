import SwiftUI

struct AudioPlaybackCarouselContent: View {
    let columns: [SpectrogramColumn]
    let isDecoding: Bool
    let displayedProgress: @MainActor () -> Double
    let storedProgress: Double
    let isPlaying: Bool
    let isSeeking: Bool
    let isPlaybackControlDisabled: Bool
    let isPlaybackControlPresented: Bool
    let playbackControlAccessibilityIdentifier: String
    let pageAccessibilityIdentifier: String
    let accessibilityPlaybackValue: String
    let audioBoostPillState: InsightAudioBoostPillState?
    let elapsedText: String?
    let durationText: String?
    let isBoostedAudioReady: Bool
    let showsBoostPreparationStatus: Bool
    let showsBoostFailure: Bool
    let onSurfaceTap: (_ progress: Double) -> Void
    let onSeekChanged: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onSeekEnded: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onAccessibilityAdjust: (_ adjustment: AudioSeekAdjustment) -> Void
    let onTogglePlayback: () -> Void
    let onToggleBoost: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isDecoding {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white)
            } else if columns.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.title)
                    Text("Audio Unavailable")
                        .font(.subheadline)
                }
                .foregroundStyle(.white.opacity(0.6))
            } else {
                AudioPlaybackSpectrogramSurface(
                    columns: columns,
                    displayedProgress: displayedProgress,
                    isPlaying: isPlaying,
                    isSeeking: isSeeking,
                    storedProgress: storedProgress,
                    accessibilityValue: accessibilityPlaybackValue,
                    onSurfaceTap: onSurfaceTap,
                    onSeekChanged: onSeekChanged,
                    onSeekEnded: onSeekEnded,
                    onAccessibilityAdjust: onAccessibilityAdjust
                )

                InsightAudioPlaybackPrimaryControl(
                    isPlaying: isPlaying,
                    isDisabled: isPlaybackControlDisabled,
                    isPresented: isPlaybackControlPresented,
                    accessibilityIdentifier:
                        playbackControlAccessibilityIdentifier,
                    action: onTogglePlayback
                )

                InsightAudioPlaybackBadges(
                    pillState: audioBoostPillState,
                    elapsedText: elapsedText,
                    durationText: durationText,
                    onToggleBoost: onToggleBoost
                )
                .animation(
                    .spring(response: 0.3, dampingFraction: 0.8),
                    value: isBoostedAudioReady
                )

                if showsBoostPreparationStatus {
                    InsightAudioPlaybackStatusMessage(text: "Boosting audio…")
                }

                if showsBoostFailure {
                    InsightAudioPlaybackStatusMessage(
                        text: "Audio boost unavailable. Playing original.",
                        backgroundOpacity: 0.68
                    )
                }
            }
        }
        .overlay {
            Color.clear
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Audio playback page")
                .accessibilityIdentifier(pageAccessibilityIdentifier)
                .allowsHitTesting(false)
        }
    }
}

private struct AudioPlaybackSpectrogramSurface: View {
    let columns: [SpectrogramColumn]
    let displayedProgress: @MainActor () -> Double
    let isPlaying: Bool
    let isSeeking: Bool
    let storedProgress: Double
    let accessibilityValue: String
    let onSurfaceTap: (_ progress: Double) -> Void
    let onSeekChanged: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onSeekEnded: (_ translationX: CGFloat, _ width: CGFloat) -> Void
    let onAccessibilityAdjust: (_ adjustment: AudioSeekAdjustment) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                AudioSpectrogramView(
                    columns: columns,
                    layout: .fitToData
                )
                .equatable()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture().onEnded { value in
                            onSurfaceTap(
                                AudioSpectrogramSeekingPolicy
                                    .normalizedProgress(
                                        locationX: value.location.x,
                                        width: proxy.size.width
                                    )
                            )
                        }
                    )

                TimelineView(.animation(paused: !isPlaying)) { _ in
                    let progress = displayedProgress()
                    ZStack(alignment: .leading) {
                        if isPlaying || isSeeking || storedProgress > 0 {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 2)
                                .offset(x: AudioSpectrogramSeekingPolicy
                                    .playmarkerCenterX(
                                        progress: progress,
                                        width: proxy.size.width
                                    ))
                                .allowsHitTesting(false)
                        }

                        Color.clear
                            .frame(
                                width: AudioSpectrogramSeekingPolicy
                                    .playmarkerHitWidth,
                                height: proxy.size.height
                            )
                            .contentShape(Rectangle())
                            .position(
                                x: min(
                                    proxy.size.width
                                        - AudioSpectrogramSeekingPolicy
                                            .playmarkerHitWidth / 2,
                                    max(
                                        AudioSpectrogramSeekingPolicy
                                            .playmarkerHitWidth / 2,
                                        AudioSpectrogramSeekingPolicy
                                            .playmarkerCenterX(
                                                progress: progress,
                                                width: proxy.size.width
                                            )
                                    )
                                ),
                                y: proxy.size.height / 2
                            )
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        onSeekChanged(
                                            value.translation.width,
                                            proxy.size.width
                                        )
                                    }
                                    .onEnded { value in
                                        onSeekEnded(
                                            value.translation.width,
                                            proxy.size.width
                                        )
                                    }
                            )
                    }
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .leading
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio position")
            .accessibilityValue(accessibilityValue)
            .accessibilityAdjustableAction { direction in
                onAccessibilityAdjust(
                    direction == .increment ? .forward : .backward
                )
            }
        }
    }
}

private struct InsightAudioPlaybackPrimaryControl: View {
    let isPlaying: Bool
    let isDisabled: Bool
    let isPresented: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
                .padding(24)
                .background(.ultraThinMaterial, in: Circle())
        }
        .disabled(isDisabled)
        .opacity(isPresented ? (isDisabled ? 0.3 : 1.0) : 0)
        .allowsHitTesting(isPresented)
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        .accessibilityLabel(isPlaying ? "Pause audio" : "Play audio")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct InsightAudioPlaybackBadges: View {
    let pillState: InsightAudioBoostPillState?
    let elapsedText: String?
    let durationText: String?
    let onToggleBoost: () -> Void

    var body: some View {
        VStack {
            Spacer()
            HStack(alignment: .center) {
                if let pillState {
                    Button(action: onToggleBoost) {
                        HStack(spacing: 4) {
                            Text(pillState.title)
                            if let systemImage = pillState.systemImage {
                                Image(systemName: systemImage)
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .insightAudioBadgeStyle()
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        pillState == .boosting || pillState == .reverting
                    )
                    .accessibilityLabel(pillState.accessibilityLabel)
                }

                Spacer()

                if let elapsedText, let durationText {
                    Text("\(elapsedText) / \(durationText)")
                        .fontDesign(.monospaced)
                        .insightAudioBadgeStyle()
                        .allowsHitTesting(false)
                        .accessibilityLabel(
                            "\(elapsedText) elapsed of \(durationText)"
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 40)
    }
}

private struct InsightAudioPlaybackStatusMessage: View {
    let text: String
    var backgroundOpacity = 0.62

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(backgroundOpacity), in: Capsule())
            .allowsHitTesting(false)
    }
}

private extension View {
    func insightAudioBadgeStyle() -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.28))
            }
            .background(
                .ultraThinMaterial,
                in: Capsule(style: .continuous)
            )
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}
