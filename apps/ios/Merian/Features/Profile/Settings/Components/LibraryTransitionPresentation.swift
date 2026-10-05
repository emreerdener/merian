import SwiftData
import SwiftUI

struct LibraryTransitionPresentation: ViewModifier {
    @Bindable var supabase: SupabaseManager
    var dependencies: LibraryTransitionPresentationDependencies = .live
    @State private var reviewsPendingChanges = false

    private var transferBlocksLibrary: Bool {
        supabase.libraryTransferResult != .completed && !supabase.isGuestUser
    }

    private var blocksLibrary: Bool {
        supabase.librarySignOutRecoveryPending || transferBlocksLibrary || supabase.libraryAccountRecoveryRequired
    }

    func body(content: Content) -> some View {
        content
            .disabled(blocksLibrary)
            .accessibilityHidden(blocksLibrary)
            .overlay {
                if supabase.librarySignOutRecoveryPending {
                    VStack(spacing: 16) {
                        Text("Finishing sign out").font(.headline)
                        Text("Your previous library is unavailable while sign-out finishes.")
                        Button("Retry") { Task { await supabase.resumeLibrarySignOut() } }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                } else if transferBlocksLibrary {
                    VStack(spacing: 16) {
                        Text("Signed in; finishing library transfer").font(.headline)
                        Text(supabase.libraryTransferResult == .needsAttention
                             ? "Transfer needs attention. Contact support before changing accounts. Recovery information is retained on this device."
                             : "Your library will be available after the transfer finishes.")
                        Button("Retry transfer") { Task { await supabase.retryLibraryTransfer() } }
                        if supabase.libraryTransferResult == .needsAttention,
                           let supportURL = URL(string: "mailto:\(PublicBrand.supportEmail)") {
                            Link("Contact support", destination: supportURL)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                } else if supabase.libraryAccountRecoveryRequired {
                    VStack(spacing: 16) {
                        Text("Recover your library account").font(.headline)
                        Text("This device has a library belonging to a previous session. Sign in to the same account to continue. Guest recovery requires its original session.")
                        Button("Sign in with Apple") { supabase.startAppleSignIn() }
                        Button("Sign in with Google") { Task { await supabase.signInWithGoogle() } }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                }
            }
            .task {
                if supabase.librarySignOutRecoveryPending {
                    await supabase.resumeLibrarySignOut()
                }
            }
            .alert("Library changes need attention", isPresented: Binding(
                get: { supabase.libraryTransitionIssue != nil },
                set: { if !$0 { supabase.libraryTransitionIssue = nil } }
            )) {
                Button("Review pending changes") { reviewsPendingChanges = true }
                Button("Keep syncing") {
                    Task { await dependencies.retrySynchronization() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(supabase.libraryTransitionIssue?.message ?? "")
            }
            .sheet(isPresented: $reviewsPendingChanges) {
                LibraryPendingChangesView(supabase: supabase, dependencies: dependencies)
            }
    }
}

struct LibraryPendingChangesView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var supabase: SupabaseManager
    var dependencies: LibraryTransitionPresentationDependencies = .live
    @Query private var scans: [OfflineQueuedScan]
    @Query private var jobs: [OfflineJobRecord]

    var body: some View {
        NavigationStack {
            List {
                Section("Restoration") {
                    Text(restorationMessage)
                    Text("Media availability is checked separately when each item is opened.")
                        .font(.footnote)
                }
                if supabase.libraryTransferResult != .completed {
                    Section("Library transfer") {
                        Text(supabase.libraryTransferResult == .needsAttention
                             ? "Transfer needs attention. Your recovery information is retained on this device."
                             : "Signed in; finishing library transfer")
                        Button("Retry transfer") { Task { await supabase.retryLibraryTransfer() } }
                    }
                }
                Section("Pending scans") {
                    ForEach(scans) { scan in
                        VStack(alignment: .leading) {
                            Text(scan.timestamp, style: .date)
                            Text(scan.queueNeedsAttention ? "Needs attention" : "Waiting to sync")
                                .foregroundStyle(.secondary)
                            Button("Review in library") { openLibrary() }
                            Button("Retry") {
                                dependencies.retryScan(scan.id)
                            }
                        }
                    }
                }
                Section("Other changes") {
                    ForEach(jobs.filter { $0.kind != .scanIngestion && $0.status != .complete && $0.status != .cancelled }) { job in
                        VStack(alignment: .leading) {
                            Text(label(for: job.kind))
                            Button("Review affected item") {
                                if let id = job.subjectId, job.kind != .cloudDeletion {
                                    dismiss()
                                    dependencies.openScan(id)
                                } else { openLibrary() }
                            }
                            Text(job.status == .needsAttention ? "Needs attention" : "Waiting to sync")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("Retry synchronization") {
                        Task { await dependencies.retrySynchronization() }
                    }
                    Button("Open library to review or repair") { openLibrary() }
                }
                Text("Account changes remain blocked until pending changes are resolved. Retrying does not discard your work. Start sign-in or sign-out again afterward.")
                    .font(.footnote)
            }
            .navigationTitle("Pending changes")
            .toolbar { Button("Done") { dismiss() } }
        }
    }

    private func openLibrary() {
        dismiss()
        dependencies.openLibrary()
    }

    private var restorationMessage: String {
        let state = dependencies.restoration()
        guard state.accountID == supabase.currentUser?.id else { return "Library restoration has not completed." }
        switch state.status {
        case .notStarted: return "Library restoration has not started."
        case .restoring: return "Restoring library"
        case .needsAttention: return "Library restoration needs attention. Retry synchronization."
        case .complete: return "Library restoration completed. Pending changes are shown below."
        }
    }

    private func label(for kind: OfflineJobKind) -> String {
        switch kind {
        case .scanIngestion: "Scan"
        case .cloudDeletion: "Scan deletion"
        case .identificationReviewSync: "Identification review"
        case .observationPublicationSync: "Identification sharing"
        case .observationReanalysisErasure: "Private photo cleanup"
        case .observationReanalysisSync: "Reanalysis"
        case .collectionSync: "Collections and memberships"
        case .speciesPreferenceSync: "Species preferences"
        case .future: "Library change"
        }
    }
}
