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

enum UnavailableVisualContext: Equatable {
    case generic
    case originalPhoto

    func presentation(isOffline: Bool) -> UnavailableVisualPresentation {
        switch (self, isOffline) {
        case (.generic, false):
            return UnavailableVisualPresentation(
                systemImage: "photo.fill",
                title: "Image unavailable",
                message: nil,
                accessibilityLabel: "Image unavailable."
            )
        case (.generic, true):
            return UnavailableVisualPresentation(
                systemImage: "wifi.slash",
                title: "Offline",
                message: "Reconnect to retry",
                accessibilityLabel: "Image unavailable while offline. Reconnect to retry."
            )
        case (.originalPhoto, false):
            return UnavailableVisualPresentation(
                systemImage: "photo.badge.exclamationmark",
                title: "Original photo unavailable",
                message: "We couldn’t load your photo, but your identification is still available.",
                accessibilityLabel: "Original photo unavailable. We couldn’t load your photo, but your identification is still available."
            )
        case (.originalPhoto, true):
            return UnavailableVisualPresentation(
                systemImage: "wifi.slash",
                title: "Original photo unavailable",
                message: "Reconnect to load your photo. Your identification is still available.",
                accessibilityLabel: "Original photo unavailable while offline. Reconnect to load your photo. Your identification is still available."
            )
        }
    }
}

struct UnavailableVisualPresentation: Equatable {
    let systemImage: String
    let title: String
    let message: String?
    let accessibilityLabel: String
}

struct UnavailableVisualsView: View {
    let isOffline: Bool
    let context: UnavailableVisualContext

    init(
        isOffline: Bool,
        context: UnavailableVisualContext = .generic
    ) {
        self.isOffline = isOffline
        self.context = context
    }

    private var presentation: UnavailableVisualPresentation {
        context.presentation(isOffline: isOffline)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)

            VStack(spacing: context == .originalPhoto ? 10 : 4) {
                Image(systemName: presentation.systemImage)
                    .font(.system(
                        size: context == .originalPhoto ? 32 : 24,
                        weight: context == .originalPhoto ? .medium : .regular
                    ))
                    .foregroundColor(.white.opacity(0.7))

                Text(presentation.title)
                    .font(context == .originalPhoto ? .headline : .system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))

                if let message = presentation.message {
                    Text(message)
                        .font(context == .originalPhoto ? .subheadline : .system(size: 9))
                        .foregroundColor(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: context == .originalPhoto ? 300 : nil)
                }
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}
