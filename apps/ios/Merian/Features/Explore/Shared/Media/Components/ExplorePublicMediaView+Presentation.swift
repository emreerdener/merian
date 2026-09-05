import AVFoundation
import SwiftUI
import UIKit

extension ExplorePublicMediaView {
    @ViewBuilder
    var audioBoostOverlay: some View {
        if let pillState = ExploreAudioBoostPillState.resolve(
            surface: surface,
            mediaKind: mediaItem.kind,
            isBoostEnabled: audioBoostEnabled,
            isPreparingBoost: isPreparingAudioBoost,
            isRevertingBoost: isRevertingAudioBoost,
            isBoostedAudioReady: boostedAudioURL != nil && !audioBoostPreparationFailed,
            hasToggleAction: onAudioBoostToggleRequested != nil
        ) {
            VStack {
                Spacer()
                HStack {
                    Button {
                        onAudioBoostToggleRequested?()
                    } label: {
                        HStack(spacing: 4) {
                            Text(pillState.title)
                            if let systemImage = pillState.systemImage {
                                Image(systemName: systemImage)
                                    .font(.system(size: 8, weight: .bold))
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.58), in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(pillState == .boosting || pillState == .reverting)
                    .accessibilityLabel(pillState.accessibilityLabel)
                    Spacer()
                }
            }
            .padding(12)
            .zIndex(5)
        } else if mediaItem.kind == .audio,
                  audioBoostEnabled,
                  boostedAudioURL != nil,
                  !audioBoostPreparationFailed {
            VStack {
                Spacer()
                HStack {
                    Text("Boosted audio")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.58), in: Capsule())
                    Spacer()
                }
            }
            .padding(12)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio boost is on")
            .zIndex(3)
        }
    }

    @ViewBuilder
    var posterImage: some View {
        if mediaItem.kind == .audio {
            if let spectrogramUrl = mediaItem.audioSpectrogramPosterUrl {
                ExploreHeroImageView(
                    imageUrl: spectrogramUrl,
                    reloadGeneration: reloadGeneration,
                    preloadedImage: nil
                )
            } else {
                ExploreAudioSpectrogramPoster(audioUrl: mediaItem.url)
            }
        } else if let posterImageUrl = mediaItem.posterImageUrl(fallback: fallbackImageUrl) {
            ExploreHeroImageView(
                imageUrl: posterImageUrl,
                reloadGeneration: reloadGeneration,
                preloadedImage: preloadedImage
            )
        } else {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                Image(systemName: "photo")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct ExploreAudioSpectrogramPoster: View {
        let audioUrl: String
        let dependencies = ExploreAudioSpectrogramDependencies.live

        @State private var spectrogram: UIImage?

        var body: some View {
            ZStack {
                Color(uiColor: .secondarySystemBackground)

                if let spectrogram {
                    Image(uiImage: spectrogram)
                        .resizable()
                        .scaledToFill()
                } else {
                    GlowPulsingSkeletonView(cornerRadius: 0)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .task(id: audioUrl) {
                spectrogram = await dependencies.loadImage(
                    audioUrl,
                    Int(MerianConfig.displayImageMaxSize)
                )
            }
            .accessibilityLabel("Audio spectrogram")
        }
    }

    @ViewBuilder
    var mediaTapLayer: some View {
        if hasMediaTapActions {
            Color.clear
                .contentShape(Rectangle())
                .gesture(mediaTapGesture)
        } else if shouldRepairHiddenPlaybackControlOnTap || shouldRevealPlaybackControlOnTap {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if shouldRepairHiddenPlaybackControlOnTap {
                        repairHiddenPlaybackControlFromTap()
                    } else {
                        revealPlaybackControlFromTap()
                    }
                }
        }
    }

    private var hasMediaTapActions: Bool {
        onSingleTap != nil || onDoubleTap != nil
    }

    var audioSeekingMode: AudioSpectrogramSeekingMode {
        mediaItem.kind == .audio && surface == .detail
            ? detailAudioSeekingMode
            : .disabled
    }

    var audioSeekLayer: some View {
        GeometryReader { proxy in
            ZStack {
                Color.clear

                switch audioSeekingMode {
                case .fullSpectrogram:
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture().onEnded { value in
                                seekAudioWithoutChangingPlayback(
                                    progress: AudioSpectrogramSeekingPolicy
                                        .normalizedProgress(
                                            locationX: value.location.x,
                                            width: proxy.size.width
                                        )
                                )
                            }
                        )
                        .simultaneousGesture(
                            audioSeekDragGesture(width: proxy.size.width)
                        )
                case .playmarkerOnly:
                    TimelineView(
                        .animation(paused: !playbackOverlayState.isPlaying)
                    ) { _ in
                        let markerCenterX = AudioSpectrogramSeekingPolicy
                            .playmarkerCenterX(
                                progress: displayedAudioPlaybackProgress,
                                width: proxy.size.width
                            )
                        let hitWidth = AudioSpectrogramSeekingPolicy
                            .playmarkerHitWidth

                        Color.clear
                            .frame(width: hitWidth, height: proxy.size.height)
                            .contentShape(Rectangle())
                            .position(
                                x: min(
                                    proxy.size.width - hitWidth / 2,
                                    max(hitWidth / 2, markerCenterX)
                                ),
                                y: proxy.size.height / 2
                            )
                            .highPriorityGesture(
                                audioSeekDragGesture(width: proxy.size.width)
                            )
                    }
                case .disabled:
                    EmptyView()
                }
            }
            .coordinateSpace(name: "ExplorePublicMediaAudioSeekSurface")
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Audio position")
            .accessibilityValue(
                "\(formattedAudioTime(audioElapsedSeconds)) of \(formattedAudioTime(audioDurationSeconds))"
            )
            .accessibilityAdjustableAction { direction in
                let adjustment: AudioSeekAdjustment = direction == .increment ? .forward : .backward
                seekAudioForAccessibility(adjustment)
            }
        }
    }

    private func audioSeekDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(
            minimumDistance: audioSeekingMode == .playmarkerOnly ? 0 : 8,
            coordinateSpace: .named("ExplorePublicMediaAudioSeekSurface")
        )
        .onChanged { value in
            guard abs(value.translation.width) > abs(value.translation.height) else {
                return
            }
            updateAudioSeek(
                progress: AudioSpectrogramSeekingPolicy.normalizedProgress(
                    locationX: value.location.x,
                    width: width
                )
            )
        }
        .onEnded { value in
            guard isAudioSeeking else { return }
            finishAudioSeek(
                progress: AudioSpectrogramSeekingPolicy.normalizedProgress(
                    locationX: value.location.x,
                    width: width
                )
            )
        }
    }

    private var hasLocalVideoPlaybackState: Bool {
        mediaItem.kind == .video || mediaItem.kind == .audio ||
            player != nil ||
            configuredVideoURL != nil ||
            playbackOverlayState.needsPlayerRebuildForRecovery
    }

    var isVideoPlaybackHost: Bool {
        hasLocalVideoPlaybackState
    }

    var shouldDisplayPlaybackControl: Bool {
        isVideoPlaybackHost &&
            showsVideoControls &&
            (playbackOverlayState.showsPlaybackControl ||
                playbackOverlayState.needsPlayerRebuildForRecovery ||
                player == nil)
    }

    private var playbackControlShowsPlayingIcon: Bool {
        playbackOverlayState.isPlaying &&
            !playbackOverlayState.needsPlayerRebuildForRecovery
    }

    private var shouldRevealPlaybackControlOnTap: Bool {
        isVideoPlaybackHost &&
            showsVideoControls &&
            !playbackOverlayState.showsPlaybackControl &&
            !shouldRepairHiddenPlaybackControlOnTap &&
            (onSingleTap == nil || playbackOverlayState.needsPlayerRebuildForRecovery)
    }

    private var shouldRepairHiddenPlaybackControlOnTap: Bool {
        isVideoPlaybackHost &&
            showsVideoControls &&
            !playbackOverlayState.showsPlaybackControl &&
            (playbackOverlayState.needsPlayerRebuildForRecovery ||
                player?.timeControlStatus != .playing)
    }

    private var mediaTapGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap?()
            },
            TapGesture().onEnded {
                if shouldRepairHiddenPlaybackControlOnTap {
                    repairHiddenPlaybackControlFromTap()
                    return
                }
                if shouldRevealPlaybackControlOnTap {
                    revealPlaybackControlFromTap()
                    return
                }
                onSingleTap?()
            }
        )
    }

    private var usesFeedCenterPlaybackZone: Bool {
        ExploreMediaInteractionPolicy.usesCenterPlaybackZone(
            surface: surface,
            mediaKind: mediaItem.kind,
            hasNavigationAction: onSingleTap != nil
        )
    }

    private var centerPlaybackGesture: some Gesture {
        ExclusiveGesture(
            TapGesture(count: 2).onEnded {
                onDoubleTap?()
            },
            TapGesture().onEnded {
                togglePlayback()
            }
        )
    }

    @ViewBuilder
    var videoOverlay: some View {
        ZStack {
            if showsVideoControls {
                if usesFeedCenterPlaybackZone {
                    feedCenterPlaybackControl
                } else if audioSeekingMode != .disabled {
                    detailAudioCenterPlaybackControl
                } else if shouldDisplayPlaybackControl {
                    Button(action: togglePlayback) {
                        Image(systemName: playbackControlShowsPlayingIcon ? "pause.fill" : "play.fill")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 58, height: 58)
                            .background(.black.opacity(playbackControlShowsPlayingIcon ? 0.32 : 0.46), in: Circle())
                            .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                        .accessibilityLabel(playbackControlAccessibilityLabel)
                    .onAppear {
                        logPlayback(
                            "control-appeared",
                            extra: "playerNil=\(player == nil) rebuild=\(playbackOverlayState.needsPlayerRebuildForRecovery)"
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeInOut(duration: 0.22), value: shouldDisplayPlaybackControl)
                }
            } else {
                VStack {
                    HStack {
                        ExploreMediaPlayIndicator()
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }

            if showsVideoControls && mediaItem.kind == .video {
                VStack {
                    HStack {
                        Spacer()

                        Button {
                            toggleMutedFromControls()
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.black.opacity(0.42), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isMuted ? "Unmute video" : "Mute video")
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playbackControlAccessibilityLabel: String {
        let medium = mediaItem.kind == .audio ? "audio" : "video"
        return playbackControlShowsPlayingIcon ? "Pause \(medium)" : "Play \(medium)"
    }

    private var detailAudioCenterPlaybackControl: some View {
        ZStack {
            if shouldDisplayPlaybackControl {
                Image(systemName: playbackControlShowsPlayingIcon ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(playbackControlShowsPlayingIcon ? 0.32 : 0.46), in: Circle())
                    .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: ExploreMediaInteractionPolicy.centerPlaybackHitSize,
            height: ExploreMediaInteractionPolicy.centerPlaybackHitSize
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: togglePlayback)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(playbackControlAccessibilityLabel)
        .accessibilityAction {
            togglePlayback()
        }
        .animation(.easeInOut(duration: 0.22), value: shouldDisplayPlaybackControl)
    }

    private var feedCenterPlaybackControl: some View {
        ZStack {
            if shouldDisplayPlaybackControl {
                Image(systemName: playbackControlShowsPlayingIcon ? "pause.fill" : "play.fill")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(playbackControlShowsPlayingIcon ? 0.32 : 0.46), in: Circle())
                    .shadow(color: .black.opacity(0.26), radius: 12, x: 0, y: 6)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(
            width: ExploreMediaInteractionPolicy.centerPlaybackHitSize,
            height: ExploreMediaInteractionPolicy.centerPlaybackHitSize
        )
        .contentShape(Rectangle())
        .gesture(centerPlaybackGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(playbackControlAccessibilityLabel)
        .accessibilityAction {
            togglePlayback()
        }
        .animation(.easeInOut(duration: 0.22), value: shouldDisplayPlaybackControl)
    }
}
