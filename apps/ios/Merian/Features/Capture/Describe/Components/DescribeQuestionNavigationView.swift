import SwiftUI

struct DescribeQuestionNavigationView: View {
    let questionCount: Int
    let activeQuestionIndex: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<questionCount, id: \.self) { index in
                    Circle()
                        .fill(
                            index == activeQuestionIndex
                                ? Color.primary
                                : Color.primary.opacity(0.2)
                        )
                        .frame(width: 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: activeQuestionIndex)

            Spacer()

            HStack(spacing: 4) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("DescribeQuestionNavigation")
    }
}

struct DescribeReanalysisHeaderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(DescribePromptCopy.reanalysisHeading)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.primary)

            Text(DescribePromptCopy.reanalysisSubheading)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
}
