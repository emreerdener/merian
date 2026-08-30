import SwiftUI

struct PaywallReviewRowView: View {
    let review: PaywallReview

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 3) {
                ForEach(0..<review.rating, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }

            Text(review.body)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.primary.opacity(0.85))
                .lineSpacing(3)
                .multilineTextAlignment(.leading)

            Text(review.author)
                .font(.system(size: 13, weight: .medium).italic())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}
