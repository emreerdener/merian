import SwiftUI
import StoreKit

struct Community: View {
    @Binding var safariUrl: URL?
    @Binding var showSafari: Bool
    
    var body: some View {
        Section {
            Button("Rate Merian") {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    SKStoreReviewController.requestReview(in: scene)
                }
            }
            Button("Suggest a Feature / Report a Bug") {
                if let url = URL(string: "mailto:support@merian.app") {
                    UIApplication.shared.open(url)
                }
            }
            Button("Community Guidelines") {
                safariUrl = URL(string: "https://merian.app/guidelines")
                showSafari = true
            }
            Button("Terms of Service & Privacy Policy") {
                safariUrl = URL(string: "https://merian.app/legal")
                showSafari = true
            }
        } header: {
            Text("Community")
        }
    }
}
