import SwiftUI

struct WikipediaReadMoreButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Read more on Wikipedia")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .foregroundColor(.blue)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
}
