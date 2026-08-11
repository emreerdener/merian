import SwiftUI
import UniformTypeIdentifiers

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
    var environmentContext: EnvironmentContext?
    var isFromGallery: Bool = false
    var subjectDistanceInMeters: Float?
    var lastCropScale: CGFloat = 1.0
    var lastCropOffset: CGSize = .zero
}

struct ImageCropperView: View {
    let image: UIImage
    let initialScale: CGFloat
    let initialOffset: CGSize
    
    // MARK: - Callbacks
    var onCrop: (Data, CGFloat, CGSize, CGFloat) -> Void
    var onCancel: () -> Void
    var onDelete: (() -> Void)?
    
    // MARK: - Interaction State
    @State private var scale: CGFloat
    @State private var currentScale: CGFloat = 1.0
    @State private var offset: CGSize
    @State private var currentOffset: CGSize = .zero
    
    init(image: UIImage, initialScale: CGFloat = 1.0, initialOffset: CGSize = .zero, onCrop: @escaping (Data, CGFloat, CGSize, CGFloat) -> Void, onCancel: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.image = image
        self.initialScale = initialScale
        self.initialOffset = initialOffset
        self.onCrop = onCrop
        self.onCancel = onCancel
        self.onDelete = onDelete
        self._scale = State(initialValue: initialScale)
        self._offset = State(initialValue: initialOffset)
    }
    
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // Calculate a perfect 1:1 square viewport dynamically inset from screen edges
                let displaySize = max(0, min(geometry.size.width, geometry.size.height) - 32)

                ZStack {
                    // 1. Immutable Canvas
                    Color.black.ignoresSafeArea()

                    VStack {
                        // The native navigation toolbar owns the top safe-area geometry.
                        // Keeping it outside this custom layout prevents a zero inset from
                        // placing destructive controls beneath system status content.
                        Spacer()

                        // 2. Optical Scaler Plane (Image Layer)
                        ZStack {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: displaySize, height: displaySize)
                                .scaleEffect(scale * currentScale)
                                .offset(
                                    x: offset.width + currentOffset.width,
                                    y: offset.height + currentOffset.height
                                )
                        }
                        .frame(width: displaySize, height: displaySize)
                        .clipShape(Rectangle())
                        .overlay(
                            Rectangle()
                                .stroke(Color.white.opacity(0.8), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                        // MARK: - Gesture Tracking
                        // Drag and Magnification simultaneously manipulate the affine geometry
                        // but they are strictly clamped to NEVER allow white space inside the box!
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let proposed = CGSize(
                                        width: offset.width + value.translation.width,
                                        height: offset.height + value.translation.height
                                    )
                                    let clamped = getClampedOffset(proposedOffset: proposed, displaySize: displaySize, activeScale: scale * currentScale)
                                    currentOffset = CGSize(
                                        width: clamped.width - offset.width,
                                        height: clamped.height - offset.height
                                    )
                                }
                                .onEnded { _ in
                                    offset.width += currentOffset.width
                                    offset.height += currentOffset.height
                                    currentOffset = .zero
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    let proposedScale = scale * value
                                    if proposedScale < 1.0 {
                                        currentScale = 1.0 / scale
                                    } else {
                                        currentScale = value
                                    }
                                }
                                .onEnded { _ in
                                    scale = max(1.0, scale * currentScale)
                                    currentScale = 1.0

                                    withAnimation(.spring()) {
                                        offset = getClampedOffset(proposedOffset: offset, displaySize: displaySize, activeScale: scale)
                                    }
                                }
                        )

                        Text("Pinch to zoom, drag to move")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.bottom, 24)

                        Spacer()

                        // 3. Confirm Button
                        Button(action: { generateCrop(displaySize: displaySize) }) {
                            Text("Confirm crop")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .tint(.accentColor)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar { cropToolbar }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    @ToolbarContentBuilder
    private var cropToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onCancel) {
                cropToolbarIcon(
                    systemName: "xmark",
                    foregroundColor: .white,
                    weight: .bold
                )
            }
            .imageOverlayToolbarButtonChrome(
                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
            )
            .accessibilityLabel("Cancel crop")
            .accessibilityIdentifier("ImageCropperCloseButton")
        }

        if let onDelete {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onDelete) {
                    cropToolbarIcon(
                        systemName: "trash",
                        foregroundColor: .red,
                        weight: .semibold
                    )
                }
                .imageOverlayToolbarButtonChrome(
                    isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground
                )
                .accessibilityLabel("Delete image")
                .accessibilityIdentifier("ImageCropperDeleteButton")
            }
        }
    }

    private func cropToolbarIcon(
        systemName: String,
        foregroundColor: Color,
        weight: Font.Weight
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: weight))
            .frame(width: 32, height: 32)
            .imageOverlayToolbarIconChrome(
                isFallbackActive: ImageOverlayToolbarChrome.shouldUseContainedBackground,
                foregroundColor: foregroundColor
            )
            .foregroundStyle(foregroundColor)
    }
    
    // MARK: - Output Generation
    // Explicitly dispatches heavy CoreGraphics memory allocations completely off the MainActor
    // to guarantee 60fps interaction during the Confirmation tap
    @MainActor
    private func generateCrop(displaySize: CGFloat) {
        HapticManager.shared.triggerMediumPulse()
        Task {
            let processedData = await ImageCropProcessor.generateCrop(
                image: image,
                displaySize: displaySize,
                scale: scale,
                currentScale: currentScale,
                offset: offset,
                currentOffset: currentOffset
            )
            onCrop(processedData, scale, offset, displaySize)
        }
    }
    
    // MARK: - Optical Path Geometry Constraints
    // Natively calculate image optical bounds to dynamically clamp offsets inside 1:1 viewports.
    // This absolutely ensures the user cannot drag the image leaving a black/white strip inside the crop!
    private func getClampedOffset(proposedOffset: CGSize, displaySize: CGFloat, activeScale: CGFloat) -> CGSize {
        let imageRatio = image.size.width / image.size.height
        
        let renderedWidth = imageRatio > 1 ? displaySize * imageRatio : displaySize
        let renderedHeight = imageRatio < 1 ? displaySize / imageRatio : displaySize
        
        let actualWidth = renderedWidth * activeScale
        let actualHeight = renderedHeight * activeScale
        
        let maxX = max(0, (actualWidth - displaySize) / 2)
        let maxY = max(0, (actualHeight - displaySize) / 2)
        
        let clampedX = min(max(proposedOffset.width, -maxX), maxX)
        let clampedY = min(max(proposedOffset.height, -maxY), maxY)
        
        return CGSize(width: clampedX, height: clampedY)
    }
}
