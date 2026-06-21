import SwiftUI

struct ExploreUnavailableStateView: View {
    let title: String
    let message: String
    var actionTitle = "Retry"
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}
