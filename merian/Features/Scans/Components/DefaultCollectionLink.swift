import SwiftUI

/// Abstracted modular list-item card natively powering fixed default collections identically.
struct DefaultCollectionLink<Destination: View>: View {
    let title: String
    let iconName: String
    let count: Int
    @ViewBuilder let destination: () -> Destination
    
    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(.secondary)    
                Text(title)   
                    .font(.headline)
                Spacer()
                Text("\(count)")
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
