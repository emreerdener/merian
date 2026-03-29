import PhotosUI
import SwiftUI

struct ActiveScanToolbar: View {
    // MARK: - Properties
    let images: [UIImage]
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    
    @State private var showTooltip: Bool = !ActiveScanToolbar.hasShownTooltipThisSession
    private static var hasShownTooltipThisSession: Bool = false
    @State private var shimmerPhase: CGFloat = -1.0
    
    // MARK: - Callbacks
    let onThumbnailTap: (Int) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void
    
    // MARK: - Body Layout
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            cancelButton
                        
            HStack(spacing: 16) {
                ActiveScanThumbnailGrid(
                    images: images,
                    selectedPhotoItems: $selectedPhotoItems,
                    onThumbnailTap: onThumbnailTap
                )
                
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
        .padding(.bottom, 24) // Accommodate the physical iPhone home indicator explicitly
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: images.count)
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
        Button(action: onCancel) {
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
                Text("Identify")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 16)
            .frame(height: 48) // Guarantees exactly 48 points!
            .background(images.isEmpty ? Color.white.opacity(0.15) : buttonColor)
            .foregroundColor(images.isEmpty ? .white.opacity(0.6) : .white)
            .clipShape(Capsule())
            // Ambient Static Glass Boundary
            .overlay(
                Capsule()
                    .strokeBorder(images.isEmpty ? .clear : buttonColor.opacity(0.4), lineWidth: 1.5)
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
                .opacity(images.isEmpty ? 0 : 1)
            )
            .shadow(color: images.isEmpty ? .clear : buttonColor.opacity(0.25), radius: 10, x: 0, y: 4)
        }
        .disabled(images.isEmpty) // Prevents submission of 0 images
        .animation(.easeInOut(duration: 0.2), value: images.isEmpty)
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
private struct ActiveScanThumbnailGrid: View {
    let images: [UIImage]
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    let onThumbnailTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<images.count, id: \.self) { index in
                Button(action: { onThumbnailTap(index) }, label: {
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                })
                .buttonStyle(PlainButtonStyle())
            }
            
            if images.count < 2 {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: max(1, 2 - images.count), matching: .images, photoLibrary: .shared()) {
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
            }
        }
    }
}

private struct ActiveScanTooltipOverlay: View {
    var body: some View {
        Text("Tap an image to edit")
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
