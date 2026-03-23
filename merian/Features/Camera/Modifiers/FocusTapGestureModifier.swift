import SwiftUI

struct FocusTapGestureModifier: ViewModifier {
    let onTap: (CGPoint) -> Void
    
    @State private var focusLocation: CGPoint? = nil
    @State private var showFocusIndicator: Bool = false
    @State private var focusTask: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        content
            .gesture(
                SimultaneousGesture(
                    TapGesture().onEnded { _ in },
                    DragGesture(minimumDistance: 0).onEnded { value in
                        let location = value.location
                        onTap(location)
                        
                        focusLocation = location
                        showFocusIndicator = true
                        
                        focusTask?.cancel()
                        focusTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            if !Task.isCancelled {
                                withAnimation(.easeOut) {
                                    showFocusIndicator = false
                                }
                            }
                        }
                    }
                )
            )
            .overlay {
                FocusIndicator(
                    showFocusIndicator: showFocusIndicator,
                    focusLocation: focusLocation
                )
            }
    }
}
