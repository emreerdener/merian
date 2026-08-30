import SwiftUI

struct FeedbackSurveyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var appSettings

    @State private var viewModel = FeedbackSurveyViewModel()

    var body: some View {
        @Bindable var viewModel = viewModel

        NavigationStack {
            Group {
                switch viewModel.step {
                case .intro:
                    introContent
                case .question(let index):
                    questionContent(index: index)
                case .success:
                    successContent
                }
            }
            .navigationTitle(viewModel.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .onAppear {
                viewModel.prepare(
                    isSubmittedStateActive:
                        FeedbackSurveyCampaign.isSubmittedStateActive(
                            submittedCampaignId:
                                appSettings.feedbackSurveySubmittedCampaignId,
                            submittedAt:
                                appSettings.feedbackSurveySubmittedAt
                        )
                )
            }
            .alert(
                "Survey not sent",
                isPresented: Binding(
                    get: { viewModel.submissionErrorMessage != nil },
                    set: {
                        if !$0 {
                            viewModel.submissionErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(
                    viewModel.submissionErrorMessage ?? "Please try again."
                )
            }
        }
    }

    private var introContent: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 20)

            VStack(spacing: 14) {
                Image("dragonfly")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 280, height: 280)
                    .accessibilityHidden(true)

                Text("Help us improve")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(
                    "We're polishing Naturebook's experience, performance, and reliability, and we'd love to hear what's working, what's confusing, and what you'd like next!"
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: 24) {
                Button {
                    withAnimation(
                        .spring(response: 0.35, dampingFraction: 0.85)
                    ) {
                        viewModel.begin()
                    }
                } label: {
                    Text("Offer feedback")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Not now") {
                    appSettings.feedbackSurveyDismissedCampaignId =
                        FeedbackSurveyCampaign.currentId
                    dismiss()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(24)
    }

    private func questionContent(index: Int) -> some View {
        VStack(spacing: 0) {
            if let validationMessage = viewModel.validationMessage {
                Text(validationMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
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

    private func questionBottomBar(index: Int) -> some View {
        VStack(spacing: 16) {
            Button {
                advanceFromQuestion(index)
            } label: {
                if viewModel.isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(
                        index == FeedbackSurveyPresentation.questionCount - 1
                            ? "Submit feedback"
                            : "Next"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isSubmitting)

            if index > 0 {
                Button("Back") {
                    withAnimation(
                        .spring(response: 0.35, dampingFraction: 0.85)
                    ) {
                        viewModel.goToQuestion(index - 1)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isSubmitting)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private func questionSection(index: Int) -> some View {
        @Bindable var viewModel = viewModel

        switch index {
        case 0:
            Section {
                FeedbackSurveySatisfactionSpectrum(
                    selectedRating: $viewModel.satisfactionRating
                )
            }
        case 1:
            Section {
                FeedbackSurveyRecommendationChoices(
                    selectedRating: $viewModel.recommendationRating
                )
            }
        case 2:
            Section("What have you used Naturebook for so far?") {
                ForEach(FeedbackSurveyFeatureUse.allCases) { feature in
                    Button {
                        viewModel.toggleFeature(feature)
                    } label: {
                        Label(
                            feature.title,
                            systemImage: viewModel.usedFeatures.contains(feature)
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }
        case 3:
            Section("Which parts feel most useful?") {
                ForEach(FeedbackSurveyUsefulFeature.allCases) { feature in
                    Button {
                        viewModel.toggleMostUsefulFeature(feature)
                    } label: {
                        Label(
                            feature.title,
                            systemImage:
                                viewModel.mostUsefulFeatures.contains(feature)
                                    ? "checkmark.circle.fill"
                                    : "circle"
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }
        case 4:
            Section(
                "What has felt confusing, slow, broken, or disappointing?"
            ) {
                TextEditor(text: $viewModel.confusingOrDisappointing)
                    .frame(minHeight: 160)
            }
        case 5:
            Section(
                "What is one thing you wish Naturebook did better next?"
            ) {
                TextEditor(text: $viewModel.wishedNext)
                    .frame(minHeight: 160)
            }
        case 6:
            Section("Have you hit any bugs or crashes?") {
                FeedbackSurveyBugStatusChoices(
                    selectedStatus: $viewModel.bugStatus
                )
            }

            if viewModel.bugStatus != .no {
                Section("Add details (optional)") {
                    TextEditor(text: $viewModel.bugDetails)
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
            Text(
                "Your notes are saved for the Naturebook team to review as we polish the beta."
            )
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            Button("Done", action: dismiss.callAsFunction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func advanceFromQuestion(_ index: Int) {
        let isFinal = index == FeedbackSurveyPresentation.questionCount - 1
        if isFinal {
            guard viewModel.shouldSubmitAfterAdvancing(from: index) else {
                return
            }
            Task { await submitSurvey() }
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            _ = viewModel.shouldSubmitAfterAdvancing(from: index)
        }
    }

    private func submitSurvey() async {
        guard let submittedAt = await viewModel.submit() else { return }
        appSettings.feedbackSurveySubmittedCampaignId =
            FeedbackSurveyCampaign.currentId
        appSettings.feedbackSurveySubmittedAt =
            submittedAt.timeIntervalSince1970
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            viewModel.presentSuccess()
        }
    }
}
