import SwiftUI
import PhotosUI

struct ActiveScanToolbar: View {
    // MARK: - Properties
    let images: [UIImage]
    @Binding var selectedPhotoItems: [PhotosPickerItem]
    
    @State private var showTooltip: Bool = !ActiveScanToolbar.hasShownTooltipThisSession
    private static var hasShownTooltipThisSession: Bool = false
    
    // MARK: - Callbacks
    let onThumbnailTap: (Int) -> Void
    let onCancel: () -> Void
    let onSubmit: () -> Void
    
    private var tooltipText: some View {
        Text("Tap an image to edit")
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white.opacity(0.9), .blue)
    }
    
    // MARK: - Body Layout
    var body: some View {
        HStack(spacing: 16) {
            cancelButton
            
            Spacer(minLength: 0)
            
            thumbnailGrid
            
            Spacer(minLength: 0)
            
            submitButton
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(glassBackground)
        .overlay(glassBorder)
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        .overlay(alignment: .top) {
            if showTooltip {
                tooltipText
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
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.15))
                .clipShape(Circle())
        }
    }
    
    private var submitButton: some View {
        Button(action: onSubmit) {
            Image(systemName: "arrow.right")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(images.isEmpty ? Color.white.opacity(0.15) : Color.blue)
                .clipShape(Circle())
        }
        .disabled(images.isEmpty)
        .animation(.easeInOut(duration: 0.2), value: images.isEmpty)
    }
    
    // MARK: - Image Grid
    private var thumbnailGrid: some View {
        HStack(spacing: 8) {
            ForEach(0..<images.count, id: \.self) { index in
                Button(action: { onThumbnailTap(index) }) {
                    Image(uiImage: images[index])
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if images.count < 2 {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: max(1, 2 - images.count), matching: .images, photoLibrary: .shared()) {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .frame(width: 56, height: 56)
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
