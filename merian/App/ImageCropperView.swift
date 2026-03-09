import SwiftUI

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct ImageCropperView: View {
    let image: UIImage
    var onCrop: (Data) -> Void
    var onCancel: () -> Void
    
    @State private var scale: CGFloat = 1.0
    @State private var currentScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var currentOffset: CGSize = .zero
    
    var body: some View {
        GeometryReader { geometry in
            let displaySize = min(geometry.size.width, geometry.size.height) - 32
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack {
                    Spacer()
                    
                    // Display View
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
                            .stroke(Color.white.opacity(0.8), lineWidth: 2)
                    )
                    .contentShape(Rectangle())
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
                            .onEnded { value in
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
                            .onEnded { value in
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
                    
                    HStack {
                        Button("Cancel") {
                            onCancel()
                        }
                        .foregroundColor(.white)
                        .padding()
                        
                        Spacer()
                        
                        Button(action: {
                            generateCrop(displaySize: displaySize)
                        }) {
                            Text("Confirm")
                                .fontWeight(.bold)
                                .foregroundColor(.yellow)
                                .padding()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
        }
    }
    
    @MainActor
    private func generateCrop(displaySize: CGFloat) {
        let finalScale = scale * currentScale
        let finalOffset = CGSize(
            width: offset.width + currentOffset.width,
            height: offset.height + currentOffset.height
        )
        
        // Target rendering exact 1024x1024 resolving size for Gemini constraints
        let renderSize: CGFloat = 1024
        
        let multiplier = renderSize / displaySize
        
        let cropContent = ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: renderSize, height: renderSize)
                .scaleEffect(finalScale)
                .offset(
                    x: finalOffset.width * multiplier,
                    y: finalOffset.height * multiplier
                )
        }
        .frame(width: renderSize, height: renderSize)
        .clipped()
        
        let renderer = ImageRenderer(content: cropContent)
        renderer.scale = 1.0 // strictly 1.0 to guarantee exactly 1024x1024 array outputs natively
        
        if let outputImage = renderer.uiImage {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task {
                let jpegData = await Task.detached(priority: .userInitiated) {
                    outputImage.jpegData(compressionQuality: 0.7) ?? Data()
                }.value
                await MainActor.run {
                    onCrop(jpegData)
                }
            }
        } else {
            // Fallback natively 
            let originalImage = image
            Task {
                let fallbackData = await Task.detached(priority: .userInitiated) {
                    originalImage.jpegData(compressionQuality: 0.7) ?? Data()
                }.value
                await MainActor.run {
                    onCrop(fallbackData)
                }
            }
        }
    }
    
    // Natively calculate image optical bounds to dynamically clamp offsets inside 1:1 viewports
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
