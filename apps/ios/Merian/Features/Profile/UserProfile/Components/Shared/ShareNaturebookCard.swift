import SwiftUI

struct ShareNaturebookCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite a friend")
                        .font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.primary)

                    Text("Help a friend identify what they find outside.")
                        .font(.system(.subheadline))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image("heart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
            }

            Button(action: {
                AppShareContent.presentShareSheet()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Share Naturebook")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .foregroundColor(Color(UIColor.systemBackground))
                .clipShape(Capsule())
            }
            .padding(.top, 8)
            .buttonStyle(BorderlessButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
