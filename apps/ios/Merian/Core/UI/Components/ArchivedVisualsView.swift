import SwiftUI

// MARK: - Core System UI Primitive
public struct ArchivedVisualsView: View {
    // MARK: - Initialization Lifecycle
    public init() {}
    
    // MARK: - Visual Layout
    public var body: some View {
        ZStack {
            // 1. Core Background Material
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                
            // 2. Centered Iconography
            VStack(spacing: 4) {
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
                Text("Visuals archived")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }
}

struct UnavailableVisualsView: View {
    let isOffline: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            VStack(spacing: 4) {
                Image(systemName: isOffline ? "wifi.slash" : "photo.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white.opacity(0.7))
                Text(isOffline ? "Offline" : "Image unavailable")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                if isOffline {
                    Text("Reconnect to retry")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isOffline
                ? "Image unavailable while offline. Reconnect to retry."
                : "Image unavailable."
        )
    }
}
