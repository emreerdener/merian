import SwiftUI

struct ReadyStepView: View {
    // MARK: - Consent State
    @Environment(ConsentManager.self) private var consentManager
    @State private var viewModel = ReadyStepViewModel()

    // MARK: - Callbacks
    let onFinish: (_ analyticsEnabled: Bool) -> Void

    // MARK: - Disclosure Copy
    static let title = ReadyConsentPresentation.title
    static let disclosure = ReadyConsentPresentation.disclosure
    static let adultStatement = ReadyConsentPresentation.adultStatement
    static let consentStatement = ReadyConsentPresentation.consentStatement
    static let analyticsStatement = ReadyConsentPresentation.analyticsStatement
    static let termsURL = ReadyConsentPresentation.termsURL
    static let requiredIndicator = ReadyConsentPresentation.requiredIndicator
    private static let illustrationSize: CGFloat = 280

    static func appendingRequiredIndicator(to statement: AttributedString) -> AttributedString {
        var markedStatement = statement
        var indicator = AttributedString(requiredIndicator)
        indicator.font = .caption2.weight(.bold)
        indicator.foregroundColor = .red
        markedStatement.append(indicator)
        return markedStatement
    }

    static var linkedConsentStatement: AttributedString {
        var statement = AttributedString(consentStatement)
        if let termsRange = statement.range(of: "terms") {
            statement[termsRange].link = termsURL
            statement[termsRange].foregroundColor = .accentColor
        }
        return appendingRequiredIndicator(to: statement)
    }

    static func canStartScanning(
        adultConfirmed: Bool,
        geminiAllowed: Bool,
        analyticsAllowed: Bool
    ) -> Bool {
        ReadyConsentPresentation.canStartScanning(
            adultConfirmed: adultConfirmed,
            geminiAllowed: geminiAllowed,
            analyticsAllowed: analyticsAllowed
        )
    }

    // MARK: - Visual Layout
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    OnboardingIllustration(
                        imageName: "bird-magnifier",
                        size: Self.illustrationSize
                    )
                        .padding(.top, OnboardingIllustration.topPadding)

                    Text(Self.title)
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)

                    disclosureText
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                    consentControls
                        .padding(.horizontal, 32)
                        .padding(.top, 24)

                    Spacer(minLength: 24)

                    actionButtons
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            viewModel.loadCurrentConsentIfNeeded(currentConsentSnapshot)
        }
        .onChange(of: consentManager.hasConfirmedCurrentAdultEligibility) { _, isConfirmed in
            viewModel.updateAdultEligibility(isConfirmed)
        }
        .onChange(of: consentManager.hasAcceptedCurrentTerms) { _, _ in
            viewModel.updateGeminiConsent(currentConsentSnapshot)
        }
        .onChange(of: consentManager.hasGrantedCurrentGeminiProcessing) { _, _ in
            viewModel.updateGeminiConsent(currentConsentSnapshot)
        }
        .onChange(of: consentManager.hasGrantedCurrentPostHogAnalytics) { _, isGranted in
            viewModel.updateAnalyticsConsent(isGranted)
        }
    }

    // MARK: - Disclosure
    private var disclosureText: some View {
        Text(Self.disclosure)
            .font(.body)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Consent
    private var consentControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            ReadyConsentToggleRow(
                isOn: adultEligibilityBinding,
                statement: Self.appendingRequiredIndicator(
                    to: AttributedString(Self.adultStatement)
                ),
                accessibilityLabel: Self.adultStatement,
                accessibilityHint: "Required to start scanning",
                accessibilityIdentifier: "Ready_AgeSwitch"
            )

            ReadyConsentToggleRow(
                isOn: geminiProcessingBinding,
                statement: Self.linkedConsentStatement,
                accessibilityLabel: Self.consentStatement,
                accessibilityHint: "Required to start scanning and allows Google Gemini to identify observations",
                accessibilityIdentifier: "Ready_GeminiTermsSwitch"
            )

            ReadyConsentToggleRow(
                isOn: analyticsBinding,
                statement: AttributedString(Self.analyticsStatement),
                accessibilityLabel: Self.analyticsStatement,
                accessibilityHint: "Optional, does not affect scanning, and can be changed later in Settings",
                accessibilityIdentifier: "Ready_AnalyticsSwitch"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var adultEligibilityBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasConfirmedAdultEligibility },
            set: { viewModel.hasConfirmedAdultEligibility = $0 }
        )
    }

    private var geminiProcessingBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasAllowedGeminiProcessing },
            set: { viewModel.hasAllowedGeminiProcessing = $0 }
        )
    }

    private var analyticsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.hasAllowedAnalytics },
            set: { viewModel.hasAllowedAnalytics = $0 }
        )
    }

    // MARK: - Actions
    private var currentConsentSnapshot: ReadyConsentSnapshot {
        ReadyConsentSnapshot(
            hasConfirmedAdultEligibility:
                consentManager.hasConfirmedCurrentAdultEligibility,
            hasAcceptedTerms: consentManager.hasAcceptedCurrentTerms,
            hasGrantedGeminiProcessing:
                consentManager.hasGrantedCurrentGeminiProcessing,
            hasGrantedAnalytics:
                consentManager.hasGrantedCurrentPostHogAnalytics
        )
    }

    private var actionButtons: some View {
        Button {
            guard viewModel.canStartScanning else { return }
            onFinish(viewModel.hasAllowedAnalytics)
        } label: {
            Text("Start scanning")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .clipShape(Capsule())
        }
        .disabled(!viewModel.canStartScanning)
        .opacity(viewModel.canStartScanning ? 1 : 0.45)
        .animation(
            .easeInOut(duration: 0.2),
            value: viewModel.canStartScanning
        )
        .accessibilityIdentifier("Ready_StartScanning")
        .accessibilityHint(
            viewModel.canStartScanning
                ? "Completes setup and opens the scanner"
                : "Turn on both required choices to start scanning"
        )
        .padding(.bottom, 32)
    }
}
