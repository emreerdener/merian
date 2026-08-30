enum FeedbackSurveyStep: Equatable {
    case intro
    case question(Int)
    case success
}

struct FeedbackSurveySatisfactionOption: Identifiable, Equatable {
    let rating: Int
    let face: String
    let label: String
    let accessibilityLabel: String

    var id: Int { rating }
}

struct FeedbackSurveyRecommendationOption: Identifiable, Equatable {
    let rating: Int
    let title: String
    let detail: String

    var id: Int { rating }
}

enum FeedbackSurveyPresentation {
    static let questionCount = 7

    static let satisfactionOptions = [
        FeedbackSurveySatisfactionOption(
            rating: 1,
            face: "😞",
            label: "Frustrated",
            accessibilityLabel: "1 out of 5, frustrated"
        ),
        FeedbackSurveySatisfactionOption(
            rating: 2,
            face: "🙁",
            label: "Rough",
            accessibilityLabel: "2 out of 5, rough"
        ),
        FeedbackSurveySatisfactionOption(
            rating: 3,
            face: "😐",
            label: "Okay",
            accessibilityLabel: "3 out of 5, okay"
        ),
        FeedbackSurveySatisfactionOption(
            rating: 4,
            face: "🙂",
            label: "Good",
            accessibilityLabel: "4 out of 5, good"
        ),
        FeedbackSurveySatisfactionOption(
            rating: 5,
            face: "😁",
            label: "Delighted",
            accessibilityLabel: "5 out of 5, delighted"
        )
    ]

    static let recommendationOptions = [
        FeedbackSurveyRecommendationOption(
            rating: 0,
            title: "Not right now",
            detail: "I would not recommend Naturebook in its current state."
        ),
        FeedbackSurveyRecommendationOption(
            rating: 4,
            title: "Maybe after more polish",
            detail: "I see the promise, but I would wait before recommending it."
        ),
        FeedbackSurveyRecommendationOption(
            rating: 7,
            title: "To the right person",
            detail: "I would recommend Naturebook to fellow nature enthusiasts."
        ),
        FeedbackSurveyRecommendationOption(
            rating: 10,
            title: "Yes, definitely",
            detail: "I would comfortably recommend Naturebook now."
        )
    ]
}
