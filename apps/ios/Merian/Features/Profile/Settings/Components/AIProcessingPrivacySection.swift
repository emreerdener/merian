import SwiftUI

/// Permission to disclose observations is independent of Naturebook's provider assignment.
/// Dormant during beta; public-release consent requires a coordinated rollout.
struct AIProcessingPrivacySection: View {
    @Environment(ConsentManager.self) private var consentManager
    @State private var isShowingDisclosure = false
    @State private var isShowingSaveError = false
    @State private var expectedOwnerUserId: UUID?
    @State private var requestedGrant = false

    private var permission: AIProcessingConsentCoordinator {
        consentManager.aiProcessingPermissions
    }

    private var permissionStatus: String {
        if permission.hasPendingOpenAIWithdrawal { return "Withdrawal pending" }
        if permission.hasGrantedOpenAI { return "Allowed" }
        if permission.hasOpenAIGrantToWithdraw { return "Review permission" }
        return "Off"
    }

    var body: some View {
        if permission.showsOpenAIChoice {
            Section {
                Button {
                    expectedOwnerUserId = permission.ownerUserId
                    requestedGrant = !permission.canProcessOpenAI && !permission.hasOpenAIGrantToWithdraw && !permission.hasPendingOpenAIWithdrawal
                    isShowingDisclosure = true
                } label: {
                    LabeledContent("OpenAI identification") {
                        Text(permissionStatus)
                    }
                }
                .disabled(!permission.canManageOpenAIPermission)
                .accessibilityIdentifier("Settings_OpenAIProcessing")
            } header: {
                Text("AI privacy")
            } footer: {
                Text("Naturebook chooses the AI service for each observation. Allowing OpenAI gives permission to share data when Naturebook uses it; it does not change the service in use.")
            }
            .alert("OpenAI identification", isPresented: $isShowingDisclosure) {
                Button(
                    requestedGrant ? ConsentPolicy.openAIGrantText : ConsentPolicy.openAIWithdrawalText,
                    role: requestedGrant ? nil : .destructive
                ) {
                    do {
                        try permission.setOpenAIEnabled(
                            requestedGrant,
                            expectedOwnerUserId: expectedOwnerUserId)
                    } catch {
                        isShowingSaveError = true
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(ConsentPolicy.openAIDisclosureText)
            }
            .onChange(of: permission.ownerUserId) { _, _ in
                isShowingDisclosure = false
            }
            .onChange(of: permission.hasCurrentAccount) { _, hasCurrentAccount in
                if !hasCurrentAccount { isShowingDisclosure = false }
            }
            .alert("Permission change not saved", isPresented: $isShowingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your OpenAI permission change could not be saved. Please try again.")
            }
        }
    }
}

/// Reuses the Settings disclosure for an observation waiting for permission.
struct AIProcessingPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                AIProcessingPrivacySection()
            }
            .navigationTitle("AI privacy")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("AIPrivacy_Done")
                }
            }
        }
    }
}
