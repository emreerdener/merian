import SwiftUI

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
    var environmentContext: EnvironmentContext? = nil
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
                            .stroke(Color.white.opacity(0.8), lineWidth: 1)
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
        
        // Capture properties securely for detached thread to prevent MainActor UI block
        let targetImage = image
        HapticManager.shared.triggerMediumPulse()
        
        Task {
            let processedData = await Task.detached(priority: .userInitiated) {
                return autoreleasepool {
                    let W = targetImage.size.width
                    let H = targetImage.size.height
                    
                    guard let cgImg = targetImage.cgImage else {
                        return targetImage.jpegData(compressionQuality: 0.7) ?? Data()
                    }
                    
                    let imageRatio = W / H
                    let renderedWidth = imageRatio > 1 ? displaySize * imageRatio : displaySize
                    let imageScale = W / renderedWidth
                    
                    // Map the SwiftUI view transforms mathematically backward to original image points
                    let dxOffsetOriginal = -finalOffset.width / finalScale * imageScale
                    let dyOffsetOriginal = -finalOffset.height / finalScale * imageScale
                    
                    let visibleWidthOriginal = displaySize / finalScale * imageScale
                    let visibleHeightOriginal = displaySize / finalScale * imageScale
                    
                    let cropX = (W - visibleWidthOriginal) / 2.0 + dxOffsetOriginal
                    let cropY = (H - visibleHeightOriginal) / 2.0 + dyOffsetOriginal
                    
                    let rawUx = cropX / W
                    let rawUy = cropY / H
                    let rawUw = visibleWidthOriginal / W
                    let rawUh = visibleHeightOriginal / H
                    
                    let ux = max(0.0, min(1.0, rawUx))
                    let uy = max(0.0, min(1.0, rawUy))
                    let uw = min(1.0 - ux, max(0.0, rawUw))
                    let uh = min(1.0 - uy, max(0.0, rawUh))
                    
                    let cW = CGFloat(cgImg.width)
                    let cH = CGFloat(cgImg.height)
                    
                    // Natively flip bounds based on Apple sensor rotation (imageOrientation)
                    var cropRect: CGRect
                    switch targetImage.imageOrientation {
                    case .up:           cropRect = CGRect(x: ux * cW, y: uy * cH, width: uw * cW, height: uh * cH)
                    case .down:         cropRect = CGRect(x: (1 - ux - uw) * cW, y: (1 - uy - uh) * cH, width: uw * cW, height: uh * cH)
                    case .left:         cropRect = CGRect(x: (1 - uy - uh) * cW, y: ux * cH, width: uh * cW, height: uw * cH)
                    case .right:        cropRect = CGRect(x: uy * cW, y: (1 - ux - uw) * cH, width: uh * cW, height: uw * cH)
                    case .upMirrored:   cropRect = CGRect(x: (1 - ux - uw) * cW, y: uy * cH, width: uw * cW, height: uh * cH)
                    case .downMirrored: cropRect = CGRect(x: ux * cW, y: (1 - uy - uh) * cH, width: uw * cW, height: uh * cH)
                    case .leftMirrored: cropRect = CGRect(x: (1 - uy - uh) * cW, y: (1 - ux - uw) * cH, width: uh * cW, height: uw * cH)
                    case .rightMirrored:cropRect = CGRect(x: uy * cW, y: ux * cH, width: uh * cW, height: uw * cH)
                    @unknown default:   cropRect = CGRect(x: ux * cW, y: uy * cH, width: uw * cW, height: uh * cH)
                    }
                    
                    // Isolate memory extraction cleanly in the background CPU pool natively
                    guard let croppedCG = cgImg.cropping(to: cropRect) else {
                        return targetImage.jpegData(compressionQuality: 0.7) ?? Data()
                    }
                    
                    // Rehydrate the image with native rotation
                    let croppedUIImage = UIImage(cgImage: croppedCG, scale: targetImage.scale, orientation: targetImage.imageOrientation)
                    
                    // Render cleanly out exactly to Gemini limits off the UI thread
                    let renderSize = CGSize(width: 768, height: 768)
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 1.0
                    let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
                    
                    let finalImage = renderer.image { _ in
                        croppedUIImage.draw(in: CGRect(origin: .zero, size: renderSize))
                    }
                    
                    return finalImage.jpegData(compressionQuality: 0.7) ?? Data()
                }
            }.value
            
            onCrop(processedData)
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
