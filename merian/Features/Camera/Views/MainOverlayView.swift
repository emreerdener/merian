import PhotosUI
import SwiftUI

struct MainOverlayView: View {
    // MARK: - Dependencies
    let activeScanImages: [UIImage]

    @AppStorage(UserDefaultsKeys.zoomSideLeft) private var zoomSideLeft: Bool = true

    // MARK: - Interface Layout
    var body: some View {
        VStack {
            Spacer()

            // MARK: - Dynamic Intelligence
            if activeScanImages.count < 2 {
                ViewfinderHints()
                    // Padding keeps hints above the fixed capture-bar + tab-bar overlay.
                    .padding(.bottom, 250)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: zoomSideLeft ? .leading : .trailing) {
            if activeScanImages.count < 2 {
                ZoomSliderView()
                    .padding(.bottom, 110)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeScanImages.count)
    }
}

// MARK: - Binding Encoders
extension Binding where Value == CameraViewModel.ActiveSheet? {
    /// Ergonomically maps an optional active sheet enumeration directly into boolean bindings for standard SwiftUI UI elements
    func mapped(to target: CameraViewModel.ActiveSheet) -> Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue == target },
            set: { newValue in
                if newValue {
                    self.wrappedValue = target
                } else if self.wrappedValue == target {
                    self.wrappedValue = nil
                }
            }
        )
    }
}
