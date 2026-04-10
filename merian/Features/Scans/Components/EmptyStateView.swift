import SwiftUI

// MARK: - Scans Feature UI Primitive
public struct EmptyStateView<Content: View>: View {
    // MARK: - Component State
    let iconName: String?
    let imageName: String?
    let title: String
    let message: String
    let content: Content
    
    // MARK: - Initialization Lifecycle
    public init(
        iconName: String? = nil,
        imageName: String? = nil,
        title: String, 
        message: String, 
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.iconName = iconName
        self.imageName = imageName
        self.title = title
        self.message = message
        self.content = content()
    }
    
    // MARK: - Visual Layout
    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            // 1. Core Visual Iconography
            if let imageName = imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .padding(.bottom, 16)
            } else if let iconName = iconName {
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
            
            // 2. Headline Messaging Layer
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            // 3. Subheadline Context
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // 4. Injected Action Hierarchy
            content
            
            Spacer()
        }
        .padding()
    }
}
