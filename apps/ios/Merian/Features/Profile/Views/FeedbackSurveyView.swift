import SwiftUI

struct FeedbackSurveyView: View {
    private enum Step {
        case intro
        case question(Int)
        case success
    }

    private struct SatisfactionOption: Identifiable {
        let rating: Int
        let face: String
        let label: String
        let accessibilityLabel: String

        var id: Int { rating }
    }

    private struct RecommendationOption: Identifiable {
        let rating: Int
        let title: String
        let detail: String

        var id: Int { rating }
    }

    private let questionCount = 7
    private let satisfactionOptions = [
        SatisfactionOption(
            rating: 1,
            face: "😞",
            label: "Frustrated",
            accessibilityLabel: "1 out of 5, frustrated"
        ),
        SatisfactionOption(
            rating: 2,
            face: "🙁",
            label: "Rough",
            accessibilityLabel: "2 out of 5, rough"
        ),
        SatisfactionOption(
            rating: 3,
            face: "😐",
            label: "Okay",
            accessibilityLabel: "3 out of 5, okay"
        ),
        SatisfactionOption(
            rating: 4,
            face: "🙂",
            label: "Good",
            accessibilityLabel: "4 out of 5, good"
        ),
        SatisfactionOption(
            rating: 5,
            face: "😁",
            label: "Delighted",
            accessibilityLabel: "5 out of 5, delighted"
        )
    ]
    private let recommendationOptions = [
        RecommendationOption(
            rating: 0,
            title: "Not right now",
            detail: "I would not recommend Merian in its current state."
        ),
        RecommendationOption(
            rating: 4,
            title: "Maybe after more polish",
            detail: "I see the promise, but I would wait before recommending it."
        ),
        RecommendationOption(
            rating: 7,
            title: "To the right person",
            detail: "I would recommend Merian to someone who fits the beta well."
        ),
        RecommendationOption(
            rating: 10,
            title: "Yes, definitely",
            detail: "I would comfortably recommend Merian now."
        )
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings

    @State private var step: Step = .intro
    @State private var satisfactionRating: Int?
    @State private var recommendationRating: Int?
    @State private var usedFeatures: Set<FeedbackSurveyFeatureUse> = []
    @State private var mostUsefulFeatures: Set<FeedbackSurveyUsefulFeature> = []
    @State private var confusingOrDisappointing = ""
    @State private var wishedNext = ""
    @State private var bugStatus: FeedbackSurveyBugStatus = .no
    @State private var bugDetails = ""
    @State private var validationMessage: String?
    @State private var submissionErrorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .intro:
                    introContent
                case .question(let index):
                    questionContent(index: index)
                case .success:
                    successContent
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .onAppear {
                if appSettings.feedbackSurveySubmittedCampaignId == FeedbackSurveyCampaign.currentId {
                    step = .success
                }
            }
            .alert("Survey not sent", isPresented: Binding(
                get: { submissionErrorMessage != nil },
                set: { if !$0 { submissionErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(submissionErrorMessage ?? "Please try again.")
            }
        }
    }

    private var navigationTitle: String {
        switch step {
        case .intro:
            "Feedback"
        case .question(let index):
            "\(index + 1) of \(questionCount)"
        case .success:
            "Thank you"
        }
    }

    private var introContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            VStack(spacing: 14) {
                Image("pw_dragonfly")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .accessibilityHidden(true)

                Text("Help us improve")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("We're polishing Merian's experience, performance, and reliability, and we'd love to hear what's working, what's confusing, and what you'd like next!")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        step = .question(0)
                    }
                } label: {
                    Text("Offer feedback")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now") {
                    appSettings.feedbackSurveyDismissedCampaignId = FeedbackSurveyCampaign.currentId
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(24)
    }

    private func questionContent(index: Int) -> some View {
        VStack(spacing: 0) {
            if let validationMessage {
                validationMessageView(validationMessage)
            }

            Form {
                questionSection(index: index)
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            questionBottomBar(index: index)
        }
    }

    private func validationMessageView(_ message: String) -> some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.top, 18)
            .padding(.bottom, 12)
    }

    private func questionBottomBar(index: Int) -> some View {
        VStack(spacing: 16) {
            Button {
                advanceFromQuestion(index)
            } label: {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(index == questionCount - 1 ? "Submit feedback" : "Next")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSubmitting)

            if index > 0 {
                Button("Back") {
                    goToQuestion(index - 1)
                }
                .buttonStyle(.borderless)
                .disabled(isSubmitting)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func questionSection(index: Int) -> some View {
        switch index {
        case 0:
            Section {
                satisfactionSpectrum
            }

        case 1:
            Section {
                recommendationChoices
            }

        case 2:
            Section("What have you used Merian for so far?") {
                ForEach(FeedbackSurveyFeatureUse.allCases) { feature in
                    Button {
                        toggleFeature(feature)
                    } label: {
                        Label(
                            feature.title,
                            systemImage: usedFeatures.contains(feature) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }

        case 3:
            Section("Which parts feel most useful?") {
                ForEach(FeedbackSurveyUsefulFeature.allCases) { feature in
                    Button {
                        toggleMostUsefulFeature(feature)
                    } label: {
                        Label(
                            feature.title,
                            systemImage: mostUsefulFeatures.contains(feature) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }

        case 4:
            Section("What has felt confusing, slow, broken, or disappointing?") {
                TextEditor(text: $confusingOrDisappointing)
                    .frame(minHeight: 160)
            }

        case 5:
            Section("What is one thing you wish Merian did better next?") {
                TextEditor(text: $wishedNext)
                    .frame(minHeight: 160)
            }

        case 6:
            Section("Have you hit any bugs or crashes?") {
                bugStatusChoices
            }

            if bugStatus != .no {
                Section("Add details (optional)") {
                    TextEditor(text: $bugDetails)
                        .frame(minHeight: 120)
                }
            }

        default:
            EmptyView()
        }
    }

    private var successContent: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Thanks for the feedback")
                .font(.title2.weight(.semibold))
            Text("Your notes are saved for the Merian team to review as we polish the beta.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private var satisfactionSpectrum: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall, how satisfied are you with Merian right now?")
                .font(.headline)

            Text("Pick the face that best matches how Merian feels today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(satisfactionOptions) { option in
                    Button {
                        satisfactionRating = option.rating
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
                                .foregroundStyle(satisfactionRating == option.rating ? .white.opacity(0.8) : .secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .padding(.vertical, 8)
                        .background(
                            satisfactionRating == option.rating
                                ? Color.accentColor
                                : Color(.secondarySystemGroupedBackground)
                        )
                        .foregroundStyle(satisfactionRating == option.rating ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                    .accessibilityAddTraits(satisfactionRating == option.rating ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var recommendationChoices: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How likely would you be to recommend Merian to another nature-curious person?")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(recommendationOptions) { option in
                    Button {
                        recommendationRating = option.rating
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: recommendationRating == option.rating ? "largecircle.fill.circle" : "circle")
                                .font(.title3)
                                .foregroundStyle(recommendationRating == option.rating ? Color.accentColor : .secondary)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(option.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            recommendationRating == option.rating
                                ? Color.accentColor.opacity(0.12)
                                : Color(.secondarySystemGroupedBackground)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(option.title). \(option.detail)")
                    .accessibilityAddTraits(recommendationRating == option.rating ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var bugStatusChoices: some View {
        VStack(spacing: 10) {
            ForEach(FeedbackSurveyBugStatus.allCases) { status in
                Button {
                    bugStatus = status
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: bugStatus == status ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(bugStatus == status ? Color.accentColor : .secondary)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(status.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(status.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        bugStatus == status
                            ? Color.accentColor.opacity(0.12)
                            : Color(.secondarySystemGroupedBackground)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(status.title). \(status.detail)")
                .accessibilityAddTraits(bugStatus == status ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }

    private func toggleFeature(_ feature: FeedbackSurveyFeatureUse) {
        if usedFeatures.contains(feature) {
            usedFeatures.remove(feature)
        } else {
            usedFeatures.insert(feature)
        }
    }

    private func toggleMostUsefulFeature(_ feature: FeedbackSurveyUsefulFeature) {
        if mostUsefulFeatures.contains(feature) {
            mostUsefulFeatures.remove(feature)
            return
        }

        if feature == .notSureYet {
            mostUsefulFeatures = [.notSureYet]
        } else {
            mostUsefulFeatures.remove(.notSureYet)
            mostUsefulFeatures.insert(feature)
        }
    }

    private func goToQuestion(_ index: Int) {
        validationMessage = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            step = .question(max(0, min(index, questionCount - 1)))
        }
    }

    private func advanceFromQuestion(_ index: Int) {
        guard validateQuestion(index) else { return }

        if index == questionCount - 1 {
            submitSurvey()
            return
        }

        goToQuestion(index + 1)
    }

    private func validateQuestion(_ index: Int) -> Bool {
        switch index {
        case 0 where satisfactionRating == nil:
            validationMessage = "Choose an overall satisfaction rating before continuing."
            return false
        case 1 where recommendationRating == nil:
            validationMessage = "Choose the recommendation option that feels closest."
            return false
        default:
            break
        }

        validationMessage = nil
        return true
    }

    private func submitSurvey() {
        guard let satisfactionRating else {
            step = .question(0)
            validationMessage = "Choose an overall satisfaction rating before continuing."
            return
        }
        guard let recommendationRating else {
            step = .question(1)
            validationMessage = "Choose the recommendation option that feels closest."
            return
        }

        let submission = FeedbackSurveySubmission(
            satisfactionRating: satisfactionRating,
            recommendationRating: recommendationRating,
            usedFeatures: FeedbackSurveyFeatureUse.allCases.filter { usedFeatures.contains($0) },
            mostUsefulFeatures: FeedbackSurveyUsefulFeature.allCases.filter { mostUsefulFeatures.contains($0) },
            confusingOrDisappointing: confusingOrDisappointing,
            wishedNext: wishedNext,
            bugStatus: bugStatus,
            bugDetails: bugDetails,
            mayFollowUp: false,
            contact: ""
        )

        isSubmitting = true
        Task {
            do {
                try await MerianNetworkClient.shared.submitFeedbackSurvey(submission)
                await MainActor.run {
                    appSettings.feedbackSurveySubmittedCampaignId = FeedbackSurveyCampaign.currentId
                    isSubmitting = false
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        step = .success
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    submissionErrorMessage = "Merian could not send your feedback. Please check your connection and try again."
                }
            }
        }
    }

}
