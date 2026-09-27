import SwiftUI

/// Collection is closed until the reviewed OpenAI rollout. Existing evidence
/// remains visible for withdrawal even when new consent collection is disabled.
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
            Section("AI privacy") {
                Button {
                    expectedOwnerUserId = permission.ownerUserId
                    requestedGrant = !permission.hasOpenAIGrantToWithdraw && !permission.hasPendingOpenAIWithdrawal
                    isShowingDisclosure = true
                } label: {
                    LabeledContent("OpenAI identification") {
                        Text(permissionStatus)
                    }
                }
                .disabled(
                    permission.ownerUserId == nil
                        || (!permission.hasOpenAIGrantToWithdraw && !permission.hasPendingOpenAIWithdrawal
                            && !permission.isOpenAICollectionEnabled)
                )
                .accessibilityIdentifier("Settings_OpenAIProcessing")
            }
            .confirmationDialog(
                "OpenAI identification", isPresented: $isShowingDisclosure,
                titleVisibility: .visible
            ) {
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
            .alert("Permission change not saved", isPresented: $isShowingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your OpenAI permission change could not be saved. Please try again.")
            }
        }
    }
}
