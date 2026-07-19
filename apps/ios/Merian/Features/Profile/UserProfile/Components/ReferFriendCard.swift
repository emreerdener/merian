import SwiftUI

struct ReferFriendCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .semibold))

                        Text("SHARE MERIAN")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }

                    Text("Invite a friend")
                        .font(.system(.title2, design: .serif))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                Spacer()

                Image("heart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
            }

            Text("Share Naturebook with someone who would love identifying what they find outside.")
                .font(.system(.subheadline))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Button(action: {
                ReferralShareContent.presentShareSheet()
            }) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Share invite")
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
