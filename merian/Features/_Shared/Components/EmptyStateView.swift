import SwiftUI

public struct EmptyStateView<Content: View>: View {
    let iconName: String
    let title: String
    let message: String
    let content: Content
    
    public init(
        iconName: String, 
        title: String, 
        message: String, 
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.iconName = iconName
        self.title = title
        self.message = message
        self.content = content()
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            content
            
            Spacer()
        }
        .padding()
    }
}
