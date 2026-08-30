import SwiftUI

struct FeedbackSurveySatisfactionSpectrum: View {
    @Binding var selectedRating: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall, how satisfied are you with Naturebook right now?")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(FeedbackSurveyPresentation.satisfactionOptions) { option in
                    Button {
                        selectedRating = option.rating
                    } label: {
                        VStack(spacing: 6) {
                            Text(option.face)
                                .font(.system(size: 28))
                                .accessibilityHidden(true)

                            Text(option.label)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.center)

                            Text("\(option.rating)")
                                .font(.caption2)
                                .foregroundStyle(
                                    selectedRating == option.rating
                                        ? .white.opacity(0.8)
                                        : .secondary
                                )
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding(.vertical, 8)
                        .background(
                            selectedRating == option.rating
                                ? Color.accentColor
                                : Color(.secondarySystemGroupedBackground)
                        )
                        .foregroundStyle(
                            selectedRating == option.rating ? .white : .primary
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 10,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                    .accessibilityAddTraits(
                        selectedRating == option.rating ? .isSelected : []
                    )
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct FeedbackSurveyRecommendationChoices: View {
    @Binding var selectedRating: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                "How likely would you be to recommend Naturebook to another nature-curious person?"
            )
            .font(.headline)

            VStack(spacing: 10) {
                ForEach(FeedbackSurveyPresentation.recommendationOptions) { option in
                    Button {
                        selectedRating = option.rating
                    } label: {
                        FeedbackSurveyRadioChoice(
                            title: option.title,
                            detail: option.detail,
                            isSelected: selectedRating == option.rating
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.title). \(option.detail)")
                    .accessibilityAddTraits(
                        selectedRating == option.rating ? .isSelected : []
                    )
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct FeedbackSurveyBugStatusChoices: View {
    @Binding var selectedStatus: FeedbackSurveyBugStatus

    var body: some View {
        VStack(spacing: 10) {
            ForEach(FeedbackSurveyBugStatus.allCases) { status in
                Button {
                    selectedStatus = status
                } label: {
                    FeedbackSurveyRadioChoice(
                        title: status.title,
                        detail: status.detail,
                        isSelected: selectedStatus == status
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(status.title). \(status.detail)")
                .accessibilityAddTraits(
                    selectedStatus == status ? .isSelected : []
                )
            }
        }
        .padding(.vertical, 6)
    }
}

private struct FeedbackSurveyRadioChoice: View {
    let title: String
    let detail: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName: isSelected
                    ? "largecircle.fill.circle"
                    : "circle"
            )
            .font(.title3)
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.12)
                : Color(.secondarySystemGroupedBackground)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
