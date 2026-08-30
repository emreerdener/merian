import SwiftData
import SwiftUI

struct DeleteAccountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PrivateScanMapStore.self) private var privateScanMapStore
    let supabase: SupabaseManager

    @State private var viewModel: DeleteAccountViewModel
    private let localDataDependencies: AccountLocalDataDependencies

    init(
        supabase: SupabaseManager,
        localDataDependencies: AccountLocalDataDependencies = .live
    ) {
        self.supabase = supabase
        self.localDataDependencies = localDataDependencies
        _viewModel = State(
            initialValue: DeleteAccountViewModel(
                dependencies: .live(supabase: supabase)
            )
        )
    }

    private var purchaseContinuityPending: Bool {
        viewModel.isPurchaseContinuityPending
    }

    private var deletionRecoveryPending: Bool {
        viewModel.isRecoveryPending
    }

    var isDeleteEnabled: Bool {
        viewModel.isDeleteEnabled(
            isAuthTransitionInProgress: supabase.isAuthTransitionInProgress
        )
    }

    var body: some View {
        @Bindable var viewModel = viewModel

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
                    TextField(
                        "Enter DELETE to confirm",
                        text: $viewModel.confirmationText
                    )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Confirm Deletion")
                } footer: {
                    if let errorMessage = viewModel.errorMessage {
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
                            if viewModel.isDeleting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Permanently Delete Account")
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isDeleteEnabled || viewModel.isDeleting)
                    .foregroundColor(isDeleteEnabled ? .white : .gray)
                    .listRowBackground(isDeleteEnabled ? Color.red : nil)
                }
            }
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(
                viewModel.isDeleting || deletionRecoveryPending
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isDeleting || deletionRecoveryPending)
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
        let didDelete = await viewModel.deleteAccount {
            localDataDependencies.purgeAllData(
                modelContext,
                privateScanMapStore.resetSensitiveState
            )
        }
        if didDelete {
            dismiss() // the parent view will catch the sign out and pop out to root
        }
    }
}
