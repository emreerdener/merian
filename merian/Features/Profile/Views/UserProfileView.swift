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
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    
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
                        UserProfileHeaderView(supabase: supabase, showPaywall: $showPaywall) {}
                            .sheet(isPresented: $showPaywall) {
                                PaywallView()
                                    .environmentObject(RevenueCatManager.shared)
                            }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                

                
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
        .preferredColorScheme(themeMode.colorScheme)
    }
}

struct UserProfilePlanComponent: View {
    @ObservedObject var revenueCat = RevenueCatManager.shared
    @Binding var showPaywall: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: revenueCat.isProActive ? "lock.open.fill" : "lock.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .semibold))
                        Text(revenueCat.isProActive ? "UNLIMITED SCANS" : "2 SCANS DAILY")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }
                    
                    Text(revenueCat.isProActive ? "Naturalist" : "Explorer")
                        .font(.system(.title, design: .serif))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if revenueCat.isProActive {
                    Image(systemName: "leaf")
                        .font(.system(size: 32))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "leaf.circle")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            
            Text(revenueCat.isProActive ? "You have unlimited identifications, offline taxonomy packs, and the Apple Watch companion natively unlocked." : "You have 2 free scans daily. Upgrade to unlock more advanced AI reasoning, unlimited identifications, audio recording, Apple Watch logging, and offline Field Queue caching.")
                .font(.system(.subheadline))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
            Button(action: { showPaywall = true }) {
                HStack {
                    Image(systemName: revenueCat.isProActive ? "gearshape" : "arrow.up.circle")
                        .font(.system(size: 20, weight: .semibold))
                    Text(revenueCat.isProActive ? "Manage subscription" : "Upgrade for more")
                        .fontWeight(.bold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .foregroundColor(Color(UIColor.systemBackground))
                .cornerRadius(16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }
}
