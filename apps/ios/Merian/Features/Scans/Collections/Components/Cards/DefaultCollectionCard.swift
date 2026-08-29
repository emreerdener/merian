import SwiftUI

struct DefaultCollectionCard<Destination: View>: View {
    let title: String
    let assetName: String
    let count: Int
    @ViewBuilder let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(spacing: 3) {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)

                VStack(spacing: 1) {
                    Text(title)
                        .font(.footnote)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Text("\(count) scans")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .multilineTextAlignment(.center)

                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .aspectRatio(
                CollectionGridCardMetrics.defaultCollectionAspectRatio,
                contentMode: .fit
            )
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(CollectionGridCardMetrics.cornerRadius)
            .clipped()
        }
        .buttonStyle(.plain)
    }
}
