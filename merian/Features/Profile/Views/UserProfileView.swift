import SwiftUI
import SwiftData
import StoreKit

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allRecords: [LocalScanRecord]
    @ObservedObject private var supabase = SupabaseManager.shared
    @ObservedObject private var revenueCat = RevenueCatManager.shared
    
    @State private var showPaywall = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    
    // Feature Toggles (AppStorage)
    @AppStorage("isExpeditionModeActive") private var isExpeditionModeActive = false
    @AppStorage("isLiveInferencePaused") private var isLiveInferencePaused = UIDevice.current.isModernIPhone
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    @AppStorage("saveToCameraRoll") private var saveToCameraRoll = true
    
    // Privacy States
    @StateObject private var viewModel = UserProfileViewModel()
    @State private var isExporting = false
    @State private var exportUrl: URL?
    @State private var showSafari = false
    @State private var safariUrl: URL?
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: - Core Profile Content
                Section {
                    VStack {
                        UserProfileHeaderView(supabase: supabase) {}
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                // Manage plan
                Section {
                    Button(action: { showPaywall = true }) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(revenueCat.isProActive ? .yellow : .primary)
                            Text("Manage plan")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(revenueCat.isProActive ? "Merian Pro" : "Free")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showPaywall) {
                        PaywallView()
                            .environmentObject(RevenueCatManager.shared)
                     }
                }
                
                // Section 2: Field & Hardware Preferences
                ProfilePreferencesSection(
                    isExpeditionModeActive: $isExpeditionModeActive,
                    isLiveInferencePaused: $isLiveInferencePaused,
                    isHapticsEnabled: $isHapticsEnabled,
                    saveToCameraRoll: $saveToCameraRoll,
                    defaultGeoprivacy: $viewModel.defaultGeoprivacy,
                    supabase: supabase
                )
                
                // Section 3: Privacy & Citizen Science
                ProfileExportSection(
                    supabase: supabase,
                    isExporting: $isExporting,
                    exportUrl: $exportUrl
                )
                
                // Section 5: Legal & Community
                ProfileCommunitySection(
                    safariUrl: $safariUrl,
                    showSafari: $showSafari
                )
                
                // Section 6: Danger Zone
                ProfileDangerZoneSection(
                    supabase: supabase,
                    isDeleting: $isDeleting,
                    showDeleteConfirmation: $showDeleteConfirmation
                )
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Profile")
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
                viewModel.fetchGeoprivacy(supabase: supabase)
                isExpeditionModeActive = HardwareOrchestrator.shared.isExpeditionModeActive
                isLiveInferencePaused = CameraManager.shared.isLiveInferencePaused
            }
            .sheet(isPresented: $showSafari) {
                if let url = safariUrl {
                    SafariView(url: url)
                }
            }
            .confirmationDialog(
                "Are you sure you want to permanently delete your account and all associated data?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account", role: .destructive) {
                    Task {
                        isDeleting = true
                        do {
                            try await MerianNetworkClient.shared.safeDeleteAccount()
                            await supabase.signOut()
                            ScanRepository.shared.purgeAllData(modelContext: modelContext)
                            dismiss()
                        } catch {
                            print("🚨 Safe delete failed: \(error.localizedDescription)")
                        }
                        isDeleting = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
