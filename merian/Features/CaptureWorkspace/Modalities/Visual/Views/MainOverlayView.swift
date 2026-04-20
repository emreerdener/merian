import PhotosUI
import SwiftUI

struct MainOverlayView: View {
    // MARK: - Dependencies
    let activeScanImages: [UIImage]
    var isRefining: Bool = false

    @AppStorage(UserDefaultsKeys.zoomSideLeft) private var zoomSideLeft: Bool = true
    @Environment(\.controlBarHeight) private var controlBarHeight

    // MARK: - Interface Layout
    var body: some View {
        VStack {
            Spacer()

            // MARK: - Dynamic Intelligence
            if activeScanImages.count < stagedImageCapacity {
                ViewfinderHints(isRefining: isRefining)
                    // Padding keeps hints consistently above the dynamic capture-bar + tab-bar overlay.
                    .padding(.bottom, controlBarHeight + 16)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: zoomSideLeft ? .leading : .trailing) {
            if activeScanImages.count < stagedImageCapacity {
                ZoomSliderView()
                    .padding(.bottom, 110)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeScanImages.count)
    }
}

// MARK: - Binding Encoders
extension Binding where Value == CaptureWorkspaceViewModel.ActiveSheet? {
    /// Ergonomically maps an optional active sheet enumeration directly into boolean bindings for standard SwiftUI UI elements
    func mapped(to target: CaptureWorkspaceViewModel.ActiveSheet) -> Binding<Bool> {
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
