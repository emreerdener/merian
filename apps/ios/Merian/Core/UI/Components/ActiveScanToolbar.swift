import PhotosUI
import SwiftUI

struct ActiveScanToolbar: View {
    // MARK: - Properties
    let stagedCapture: StagedCapture
    let isRefining: Bool
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    @Environment(AppSettings.self) private var appSettings

    @State private var showTooltip: Bool = !ActiveScanToolbar.hasShownTooltipThisSession
    private static var hasShownTooltipThisSession: Bool = false
    @State private var shimmerPhase: CGFloat = -1.0
    @State private var isPhotoPickerPresented: Bool = false

    // MARK: - Callbacks
    let onThumbnailTap: (Int) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void
    let onDescriptionTap: (Int) -> Void
    let onVideoTap: (Int) -> Void

    // MARK: - Body Layout
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            cancelButton

            HStack(spacing: 16) {
                ForEach(orderedNodes) { node in
                    switch node {
                    case .image(let uiImage, let index, _):
                        Button(action: { onThumbnailTap(index) }, label: {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                        })
                        .buttonStyle(PlainButtonStyle())
                        
                    case .description(let index, _):
                        Button(action: { onDescriptionTap(index) }) {
                            StagedDescriptionBadge()
                        }
                        .buttonStyle(.plain)
                        
                    case .audio:
                        Button(action: {}) {
                            StagedAudioBadge()
                        }
                        .buttonStyle(.plain)

                    case .video(let uiImage, let index, _):
                        Button(action: { onVideoTap(index) }) {
                            ZStack(alignment: .bottomTrailing) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))

                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(Color.black.opacity(0.62))
                                    .clipShape(Circle())
                                    .offset(x: 1, y: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                let currentLimit = (appSettings.isMultiCaptureEnabled || isRefining) ? stagedCaptureCapacity : 1
                if orderedNodes.count < currentLimit {
                    // Use isPresented + explicit keyboard resign so iOS cannot restore the
                    // text field as first responder when the picker dismisses — that restoration
                    // fires keyboardWillShow and hides the toolbar behind the keyboard overlay.
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        isPhotoPickerPresented = true
                    }) {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .photosPicker(
                        isPresented: $isPhotoPickerPresented,
                        selection: $selectedPhotoItems,
                        maxSelectionCount: max(1, stagedCapture.availableSlots(limit: currentLimit)),
                        matching: .images,
                        photoLibrary: .shared()
                    )
                }

                submitButton
            }
            .padding(8)
            .background(glassBackground)
            .overlay(glassBorder)
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .overlay(alignment: .top) {
            if showTooltip {
                ActiveScanTooltipOverlay()
                    .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.bottom, 24)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: stagedCapture.images.count)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: stagedCapture.observationContexts.count)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: stagedCapture.audios.count)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: stagedCapture.videos.count)
        .task {
            if showTooltip {
                ActiveScanToolbar.hasShownTooltipThisSession = true
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation { showTooltip = false }
            }
        }
    }
}

// MARK: - Internal Components
extension ActiveScanToolbar {
    
    // MARK: - Buttons
    private var cancelButton: some View {
        Button {
            HapticManager.shared.triggerMediumPulse(source: "capture.staged.cancel")
            onCancel()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 24, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.5),
                                    Color.white.opacity(0.1),
                                    Color.white.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                )
        }
    }
    
    private var submitButton: some View {
        let buttonColor = Color(red: 0.11, green: 0.52, blue: 0.28)
        
        return Button(action: onSubmit) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.2")
                    .font(.system(size: 18, weight: .semibold))
                Text(isRefining ? "Analyze" : "Identify")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .frame(height: 48) // Guarantees exactly 48 points!
            .background(stagedCapture.isEmpty ? Color.white.opacity(0.15) : buttonColor)
            .foregroundColor(stagedCapture.isEmpty ? .white.opacity(0.6) : .white)
            .clipShape(Capsule())
            // Ambient Static Glass Boundary
            .overlay(
                Capsule()
                    .strokeBorder(stagedCapture.isEmpty ? .clear : buttonColor.opacity(0.4), lineWidth: 1.5)
            )
            // Animated Holographic Glare Sweep
            .overlay(
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white.opacity(0.9), location: 0.5),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: geo.size.width)
                        .offset(x: shimmerPhase * geo.size.width * 2)
                        .blendMode(.screen)
                        .mask(
                            Capsule().stroke(lineWidth: 1.5)
                        )
                }
                .allowsHitTesting(false) // Prevents the geometry overlay from blocking taps
                .opacity(stagedCapture.isEmpty ? 0 : 1)
            )
            .shadow(color: stagedCapture.isEmpty ? .clear : buttonColor.opacity(0.25), radius: 10, x: 0, y: 4)
        }
        .disabled(stagedCapture.isEmpty) // Prevents submission of 0 images
        .animation(.easeInOut(duration: 0.2), value: stagedCapture.isEmpty)
        .onAppear {
            withAnimation(.linear(duration: 4.5).repeatForever(autoreverses: false)) {
                shimmerPhase = 2.5
            }
        }
    }
   
    // MARK: - Image Grid
    // Moved to private struct ActiveScanThumbnailGrid below to simplify evaluation bounds

    // MARK: - Liquid Glass Container
    private var glassBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
    }
    
    private var glassBorder: some View {
        Capsule()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.5),
                        Color.white.opacity(0.1),
                        Color.white.opacity(0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.5
            )
    }
}

// MARK: - Extracted Private Subviews

private enum StagedNode: Identifiable {
    case image(uiImage: UIImage, index: Int, addedAt: Date)
    case description(index: Int, addedAt: Date)
    case audio(index: Int, addedAt: Date)
    case video(uiImage: UIImage, index: Int, addedAt: Date)

    var id: String {
        switch self {
        case .image(_, let index, _): return "img_\(index)"
        case .description(let index, _): return "desc_\(index)"
        case .audio(let index, _): return "audio_\(index)"
        case .video(_, let index, _): return "video_\(index)"
        }
    }
    
    var addedAt: Date {
        switch self {
        case .image(_, _, let d): return d
        case .description(_, let d): return d
        case .audio(_, let d): return d
        case .video(_, _, let d): return d
        }
    }
}

extension ActiveScanToolbar {
    private var orderedNodes: [StagedNode] {
        var nodes: [StagedNode] = []
        for node in stagedCapture.orderedNodes {
            switch node {
            case .image(let index, let stagedImage):
                nodes.append(.image(uiImage: stagedImage.uiImage, index: index, addedAt: stagedImage.addedAt))
            case .audio(let index, let stagedAudio):
                nodes.append(.audio(index: index, addedAt: stagedAudio.addedAt))
            case .video(let index, let stagedVideo):
                if let coverImage = stagedVideo.coverImage {
                    nodes.append(.video(uiImage: coverImage.uiImage, index: index, addedAt: stagedVideo.addedAt))
                }
            case .description(let index, let stagedObservationContext):
                nodes.append(.description(index: index, addedAt: stagedObservationContext.addedAt))
            }
        }
        return nodes.sorted { $0.addedAt < $1.addedAt }
    }
}

/// Compact badge that appears in the toolbar when a describe description has been
/// staged alongside images — signals a combined multi-modal submission to the user.
private struct StagedDescriptionBadge: View {
    var body: some View {
        Image(systemName: "text.alignleft")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(Color.primary)
            )
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

/// Compact badge that appears in the toolbar when an audio clip has been
/// staged. Signals an audio modality submission to the user.
private struct StagedAudioBadge: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color(UIColor.systemBackground))
            .frame(width: 48, height: 48)
            .background(
                Circle()
                    .fill(Color.primary)
            )
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }
}

private struct ActiveScanTooltipOverlay: View {
    var body: some View {
        Text("Tap to edit")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white.opacity(0.9), .blue)
            .font(.caption.weight(.medium))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.4))
                    .background(.ultraThinMaterial, in: Capsule())
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .offset(y: -40) // Floats above the top edge of the toolbar without affecting layout
    }
}
