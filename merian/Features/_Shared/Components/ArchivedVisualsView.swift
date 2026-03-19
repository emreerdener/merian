import SwiftUI

public struct ArchivedVisualsView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                
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
