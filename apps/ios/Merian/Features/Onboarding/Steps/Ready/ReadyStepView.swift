import SwiftUI

struct ReadyStepView: View {
    // MARK: - Consent State
    @Environment(ConsentManager.self) private var consentManager
    @State private var hasConfirmedAdultEligibility = false
    @State private var hasAllowedGeminiProcessing = false
    @State private var hasAllowedAnalytics = false
    @State private var hasLoadedCurrentConsent = false

    // MARK: - Callbacks
    let onFinish: (_ analyticsEnabled: Bool) -> Void

    // MARK: - Disclosure Copy
    static let title = "One last step"
    static let disclosure = ConsentPolicy.geminiDisclosureText
    static let adultStatement = ConsentPolicy.adultConfirmationText
    static let consentStatement = ConsentPolicy.combinedAcceptanceText
    static let analyticsStatement = ConsentPolicy.analyticsDisclosureText
    static let termsURL = PublicBrand.websiteURL(path: "terms")
    static let requiredIndicator = " *"

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
        analyticsAllowed _: Bool
    ) -> Bool {
        adultConfirmed && geminiAllowed
    }

    // MARK: - Visual Layout
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    OnboardingIllustration(imageName: "bird-magnifier")
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
            guard !hasLoadedCurrentConsent else { return }
            loadCurrentConsentState()
            hasLoadedCurrentConsent = true
        }
        .onChange(of: consentManager.hasConfirmedCurrentAdultEligibility) { _, isConfirmed in
            guard hasLoadedCurrentConsent else { return }
            hasConfirmedAdultEligibility = isConfirmed
        }
        .onChange(of: consentManager.hasAcceptedCurrentTerms) { _, _ in
            guard hasLoadedCurrentConsent else { return }
            loadCurrentGeminiConsentState()
        }
        .onChange(of: consentManager.hasGrantedCurrentGeminiProcessing) { _, _ in
            guard hasLoadedCurrentConsent else { return }
            loadCurrentGeminiConsentState()
        }
        .onChange(of: consentManager.hasGrantedCurrentPostHogAnalytics) { _, isGranted in
            guard hasLoadedCurrentConsent else { return }
            hasAllowedAnalytics = isGranted
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
        VStack(alignment: .center, spacing: 18) {
            consentRow(
                isOn: $hasConfirmedAdultEligibility,
                statement: Self.adultStatement,
                isRequired: true,
                accessibilityHint: "Required to start scanning",
                accessibilityIdentifier: "Ready_AgeSwitch"
            )

            linkedGeminiConsentRow

            consentRow(
                isOn: $hasAllowedAnalytics,
                statement: Self.analyticsStatement,
                accessibilityHint: "Optional, does not affect scanning, and can be changed later in Settings",
                accessibilityIdentifier: "Ready_AnalyticsSwitch"
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func consentRow(
        isOn: Binding<Bool>,
        statement: String,
        isRequired: Bool = false,
        accessibilityHint: String,
        accessibilityIdentifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: isOn) {
                EmptyView()
            }
            .labelsHidden()
            .tint(.accentColor)
            .fixedSize()
            .accessibilityLabel(statement)
            .accessibilityHint(accessibilityHint)
            .accessibilityIdentifier(accessibilityIdentifier)

            Text(
                isRequired
                    ? Self.appendingRequiredIndicator(to: AttributedString(statement))
                    : AttributedString(statement)
            )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var linkedGeminiConsentRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: $hasAllowedGeminiProcessing) {
                EmptyView()
            }
            .labelsHidden()
            .tint(.accentColor)
            .fixedSize()
            .accessibilityLabel(Self.consentStatement)
            .accessibilityHint(
                "Required to start scanning and allows Google Gemini to identify observations"
            )
            .accessibilityIdentifier("Ready_GeminiTermsSwitch")

            Text(Self.linkedConsentStatement)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Actions
    private var hasRequiredConsent: Bool {
        Self.canStartScanning(
            adultConfirmed: hasConfirmedAdultEligibility,
            geminiAllowed: hasAllowedGeminiProcessing,
            analyticsAllowed: hasAllowedAnalytics
        )
    }

    private func loadCurrentConsentState() {
        hasConfirmedAdultEligibility = consentManager.hasConfirmedCurrentAdultEligibility
        loadCurrentGeminiConsentState()
        hasAllowedAnalytics = consentManager.hasGrantedCurrentPostHogAnalytics
    }

    private func loadCurrentGeminiConsentState() {
        hasAllowedGeminiProcessing = consentManager.hasAcceptedCurrentTerms
            && consentManager.hasGrantedCurrentGeminiProcessing
    }

    private var actionButtons: some View {
        Button {
            guard hasRequiredConsent else { return }
            onFinish(hasAllowedAnalytics)
        } label: {
            Text("Start scanning")
                .font(.headline)
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .clipShape(Capsule())
        }
        .disabled(!hasRequiredConsent)
        .opacity(hasRequiredConsent ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: hasRequiredConsent)
        .accessibilityIdentifier("Ready_StartScanning")
        .accessibilityHint(
            hasRequiredConsent
                ? "Completes setup and opens the scanner"
                : "Turn on both required choices to start scanning"
        )
        .padding(.bottom, 32)
    }
}
