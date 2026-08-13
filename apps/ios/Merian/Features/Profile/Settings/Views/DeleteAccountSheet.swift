import SwiftData
import SwiftUI

struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let supabase: SupabaseManager
    
    @State private var confirmationText: String = ""
    @State private var isDeleting: Bool = false
    @State private var errorMessage: String?

    private var purchaseContinuityPending: Bool {
        RevenueCatManager.shared.isPurchaseIdentityHandoffPending
    }

    private var deletionRecoveryPending: Bool {
        AccountDeletionLocalCleanupStore.isPending()
    }
    
    var isDeleteEnabled: Bool {
        confirmationText == "DELETE" &&
            !purchaseContinuityPending &&
            !deletionRecoveryPending &&
            !supabase.isAuthTransitionInProgress
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("This permanently removes your account and account-owned data. It cannot be reversed.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            consequenceRow(
                                icon: "person.crop.circle.badge.xmark",
                                text: "Your profile, account identifier, public attribution, and community content will be removed."
                            )
                            consequenceRow(
                                icon: "icloud.slash",
                                text: "Your uploaded media, private notes, life list, and collection progress will be deleted."
                            )
                            consequenceRow(
                                icon: "leaf.circle",
                                text: "Scientific observations you submitted—including exact coordinates, time, and taxonomy—will remain without account attribution."
                            )
                            consequenceRow(
                                icon: "creditcard",
                                text: "Deleting your account does not cancel an Apple subscription. Cancel it separately to stop renewal."
                            )
                            consequenceRow(
                                icon: "apple.logo",
                                text: "Naturebook revokes Sign in with Apple automatically when a server token is available. Legacy accounts receive Apple’s manual revocation steps after deletion is accepted."
                            )
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Consequences")
                }
                
                Section {
                    TextField("Enter DELETE to confirm", text: $confirmationText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Confirm Deletion")
                } footer: {
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    } else if purchaseContinuityPending {
                        Text("Finish signing out before deleting this account.")
                            .foregroundColor(.red)
                    } else {
                        Text("Type the word DELETE in all caps to enable account deletion.")
                    }
                }
                
                Section {
                    Button(action: {
                        Task { await performDeletion() }
                    }) {
                        HStack {
                            Spacer()
                            if isDeleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Permanently Delete Account")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isDeleteEnabled || isDeleting)
                    .foregroundColor(isDeleteEnabled ? .white : .gray)
                    .listRowBackground(isDeleteEnabled ? Color.red : nil)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isDeleting || deletionRecoveryPending)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isDeleting || deletionRecoveryPending)
                }
            }
        }
    }
    
    private func consequenceRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.red)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func performDeletion() async {
        guard !supabase.hasPendingPurchaseIdentityHandoffFailClosed() else {
            errorMessage = "Finish signing out before deleting this account."
            return
        }
        isDeleting = true
        errorMessage = nil
        
        do {
            if deletionRecoveryPending {
                guard await supabase
                    .resumePendingAccountDeletionLocalCleanup(
                        purgeLocalData: {
                            ScanRepository.shared.purgeAllData(
                                modelContext: modelContext
                            )
                        }
                    ) else {
                    errorMessage =
                        "Account deletion is still being confirmed. Keep Naturebook open and connected; it will retry safely."
                    isDeleting = false
                    return
                }
            } else {
                _ = try await supabase.deleteCurrentAccount {
                    ScanRepository.shared.purgeAllData(
                        modelContext: modelContext
                    )
                }
            }
            dismiss() // the parent view will catch the sign out and pop out to root
        } catch {
            MerianLog.general.error(
                "Account deletion failed; kind=\(MerianLog.errorKind(error), privacy: .public)"
            )
            if AccountDeletionLocalCleanupStore.isPending() {
                errorMessage =
                    "Account deletion is still being confirmed. Keep Naturebook open and connected; it will retry safely."
            } else if MerianNetworkClient.stableEdgeErrorCode(from: error)
                == "purchase_continuity_pending" {
                errorMessage = "Finish signing out before deleting this account."
            } else {
                errorMessage = "Failed to delete account. Please try again or contact support."
            }
            isDeleting = false
        }
    }
}
