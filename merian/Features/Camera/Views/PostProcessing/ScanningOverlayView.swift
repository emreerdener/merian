import SwiftUI
import UIKit

// MARK: - Semantic Modal Anchor
// Acts as the global UI isolation layer, completely blacking out the camera viewfinder
// while presenting the geometric snapshot at a 1:1 ratio.
struct ScanningOverlayView: View {
    // MARK: - Dependencies
    let images: [UIImage]
    let scanningPhaseText: String
    let onDismiss: () -> Void

    // MARK: - Animation State
    @State private var pillScale: CGFloat = 1.0
    @State private var bracketsVisible: Bool = false

    // MARK: - View Engine
    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Floating Status Pill
                // Frosted glass capsule frames the phase text as a distinct UI element.
                Text(scanningPhaseText)
                    .id(scanningPhaseText)
                    .font(.system(.callout, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 10)),
                        removal: .opacity.combined(with: .offset(y: -10))
                    ))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: scanningPhaseText)
                    .scaleEffect(pillScale)
                    .onChange(of: scanningPhaseText) { _, _ in
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
                            pillScale = 1.04
                        }
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7).delay(0.1)) {
                            pillScale = 1.0
                        }
                    }

                // Optical Scaler Plane
                HStack(spacing: 4) {
                    ForEach(0..<images.count, id: \.self) { index in
                        Image(uiImage: images[index])
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .clipped()
                    }
                }
                .aspectRatio(1.0, contentMode: .fit)
                // Corner brackets sit inside the clip so they respect the squircle boundary.
                .overlay(ScanCornerBrackets(visible: bracketsVisible))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .premiumScanningOverlay()
                .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 15)
                .padding(.horizontal, 32)
                .onAppear {
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                        bracketsVisible = true
                    }
                }
            }

            // Top-left X Button
            Button(action: {
                HapticManager.shared.triggerLightImpact()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 24)
            .padding(.top, 16)
        }
    }
}

// MARK: - Scan Corner Brackets

private struct ScanCornerBrackets: View {
    let visible: Bool

    var body: some View {
        ZStack {
            bracket(.topLeft,     alignment: .topLeading)
            bracket(.topRight,    alignment: .topTrailing)
            bracket(.bottomLeft,  alignment: .bottomLeading)
            bracket(.bottomRight, alignment: .bottomTrailing)
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.88)
    }

    private func bracket(_ corner: CornerBracketShape.Corner, alignment: Alignment) -> some View {
        CornerBracketShape(corner: corner)
            .stroke(Color.white.opacity(0.7), lineWidth: 2)
            .frame(width: 22, height: 22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .padding(14)
    }
}

private struct CornerBracketShape: Shape {
    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    let corner: Corner

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)
        let r: CGFloat = 6
        switch corner {
        case .topLeft:
            p.move(to: CGPoint(x: maxX, y: minY))
            p.addLine(to: CGPoint(x: minX + r, y: minY))
            p.addArc(tangent1End: CGPoint(x: minX, y: minY),
                     tangent2End: CGPoint(x: minX, y: minY + r), radius: r)
            p.addLine(to: CGPoint(x: minX, y: maxY))
        case .topRight:
            p.move(to: CGPoint(x: minX, y: minY))
            p.addLine(to: CGPoint(x: maxX - r, y: minY))
            p.addArc(tangent1End: CGPoint(x: maxX, y: minY),
                     tangent2End: CGPoint(x: maxX, y: minY + r), radius: r)
            p.addLine(to: CGPoint(x: maxX, y: maxY))
        case .bottomLeft:
            p.move(to: CGPoint(x: minX, y: minY))
            p.addLine(to: CGPoint(x: minX, y: maxY - r))
            p.addArc(tangent1End: CGPoint(x: minX, y: maxY),
                     tangent2End: CGPoint(x: minX + r, y: maxY), radius: r)
            p.addLine(to: CGPoint(x: maxX, y: maxY))
        case .bottomRight:
            p.move(to: CGPoint(x: minX, y: maxY))
            p.addLine(to: CGPoint(x: maxX - r, y: maxY))
            p.addArc(tangent1End: CGPoint(x: maxX, y: maxY),
                     tangent2End: CGPoint(x: maxX, y: maxY - r), radius: r)
            p.addLine(to: CGPoint(x: maxX, y: minY))
        }
        return p
    }
}
