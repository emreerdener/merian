import SwiftUI
import SwiftData
import StoreKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
    @State private var defaultGeoprivacy = "open"
    @State private var isExporting = false
    @State private var exportUrl: URL?
    @State private var showSafari = false
    @State private var safariUrl: URL?

    var body: some View {
        NavigationStack {
            List {
                // Section 1: Identity & Subscription
                Section {
                    Button(action: { showPaywall = true }) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(revenueCat.isProActive ? .yellow : .primary)
                            Text("Manage plan")
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(revenueCat.isProActive ? "Merian Pro" : "Free")
                                .foregroundColor(.secondary)
                        }
                    }
                    .sheet(isPresented: $showPaywall) {
                        PaywallView()
                            .environmentObject(RevenueCatManager.shared)
                    }
                    
                    UserProfileAuthSection(supabase: supabase)
                        .buttonStyle(PlainButtonStyle())
                        .padding(.vertical, 4)
                } header: {
                    Text("Account")
                }
                
                // Section 2: Field & Hardware Preferences
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Expedition Mode", isOn: $isExpeditionModeActive)
                            .onChange(of: isExpeditionModeActive) { _, newValue in
                                HardwareOrchestrator.shared.isExpeditionModeActive = newValue
                                HardwareOrchestrator.shared.evaluateConstraints()
                            }
                        Text("Limits camera to 24fps, disables heavy glass blurs, and pauses cellular queue syncing to maximize battery life off-grid.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Legacy Viewfinder", isOn: $isLiveInferencePaused)
                            .onChange(of: isLiveInferencePaused) { _, newValue in
                                CameraManager.shared.isLiveInferencePaused = newValue
                            }
                        Text("Disables live AI scanning hints before capturing. Recommended for devices experiencing high thermal loads or heat warnings.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    
                    Toggle("System Haptics", isOn: $isHapticsEnabled)
                    Toggle("Save to Camera Roll", isOn: $saveToCameraRoll)
                } header: {
                    Text("Field & Hardware")
                }
                
                // Section 3: Privacy & Citizen Science
                Section {
                    NavigationLink {
                        SettingsGeoprivacyView(defaultGeoprivacy: $defaultGeoprivacy) { newValue in
                            Task {
                                guard let userId = supabase.currentUser?.id else { return }
                                do {
                                    try await supabase.client.from("users")
                                        .update(["default_geoprivacy": newValue])
                                        .eq("id", value: userId)
                                        .execute()
                                } catch {
                                    print("Failed to update geoprivacy: \(error)")
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Default Geoprivacy")
                            Spacer()
                            Text(defaultGeoprivacy.capitalized)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if !supabase.isGuestUser {
                        // Export Scans
                        if let url = exportUrl {
                            ShareLink(item: url) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Download Scans (DwC-A)")
                                }
                            }
                        } else {
                            Button(action: {
                                Task.detached(priority: .userInitiated) {
                                    await MainActor.run { isExporting = true }
                                    do {
                                        let url = try await MerianNetworkClient.shared.exportDwcA(scope: "user")
                                        await MainActor.run {
                                            self.exportUrl = url
                                            self.isExporting = false
                                        }
                                    } catch {
                                        print("Export failed: \(error)")
                                        await MainActor.run { isExporting = false }
                                    }
                                }
                            }) {
                                HStack {
                                    if isExporting {
                                        ProgressView().padding(.trailing, 8)
                                    }
                                    Text("Export Scans (DwC-A)")
                                }
                            }
                            .disabled(isExporting)
                        }
                    } else {
                        Text("Sign in with Apple to export data")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    }
                } header: {
                    Text("Privacy & Science")
                } footer: {
                    Text("Darwin Core Archive (DwC-A) exports package your entire cloud collection into a standardized scientific format.")
                }
                
                // Section 4: Data Management
                Section {
                    Button(action: {
                        Task {
                            ImageCache.shared.clearCache()
                            let cachesDir = URL.cachesDirectory
                            if let enumerator = FileManager.default.enumerator(at: cachesDir, includingPropertiesForKeys: nil) {
                                while let fileURL = enumerator.nextObject() as? URL {
                                    if fileURL.pathExtension == "jpg" && !fileURL.lastPathComponent.contains("_temp_upload") {
                                        try? FileManager.default.removeItem(at: fileURL)
                                    }
                                }
                            }
                            HapticManager.shared.triggerSuccessPulse()
                        }
                    }) {
                        Text("Clear Local Cache")
                    }
                }
                
                // Section 5: Legal & Community
                Section {
                    Button("Rate Merian") {
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                            SKStoreReviewController.requestReview(in: scene)
                        }
                    }
                    Button("Suggest a Feature / Report a Bug") {
                        if let url = URL(string: "mailto:support@merian.app") {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Community Guidelines") {
                        safariUrl = URL(string: "https://merian.app/guidelines")
                        showSafari = true
                    }
                    Button("Terms of Service & Privacy Policy") {
                        safariUrl = URL(string: "https://merian.app/legal")
                        showSafari = true
                    }
                } header: {
                    Text("Community")
                }
                
                // Section 6: Danger Zone
                Section {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Text("Delete Account & Data")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(.red)
                    }
                    .disabled(isDeleting)
                }
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                    }
                }
            }
            .onAppear {
                // Fetch existing geoprivacy if authenticated
                if !supabase.isGuestUser, let user = supabase.currentUser {
                    Task {
                        // Normally this is cached in Supabase User.userMetadata but let's query it freshly:
                        do {
                            struct CurrentSettings: Decodable { let default_geoprivacy: String }
                            let response: CurrentSettings = try await supabase.client.from("users")
                                .select("default_geoprivacy")
                                .eq("id", value: user.id)
                                .single()
                                .execute()
                                .value
                            self.defaultGeoprivacy = response.default_geoprivacy
                        } catch {
                            print("Error fetching geoprivacy: \(error)")
                        }
                    }
                }
                
                // Ensure toggles map to live state
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

struct SettingsGeoprivacyView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var defaultGeoprivacy: String
    
    // Required to trigger network updates immediately when selection changes
    let onGeoprivacyChanged: (String) -> Void
    
    var body: some View {
        List {
            Section {
                GeoprivacyOptionRow(
                    title: "Open",
                    description: "Shares exact coordinate data. This is crucial for citizen science, researchers, and global biodiversity tracking.",
                    systemImage: "globe.americas.fill",
                    iconColor: .green,
                    isSelected: defaultGeoprivacy == "open"
                ) {
                    selectGeoprivacy("open")
                }
                
                GeoprivacyOptionRow(
                    title: "Obscured",
                    description: "Randomizes the location to a large 50km radius. Protects exact locations of your property or rare species from poachers.",
                    systemImage: "viewfinder.circle.fill",
                    iconColor: .yellow,
                    isSelected: defaultGeoprivacy == "obscured"
                ) {
                    selectGeoprivacy("obscured")
                }
                
                GeoprivacyOptionRow(
                    title: "Private",
                    description: "Completely hides coordinates from the public Discovery Feed. Only you can view the mapped locations of these scans.",
                    systemImage: "lock.shield.fill",
                    iconColor: .red,
                    isSelected: defaultGeoprivacy == "private"
                ) {
                    selectGeoprivacy("private")
                }
            } header: {
                Text("Default Visibility")
            } footer: {
                Text("Your default Geoprivacy will apply to all future scans automatically. You can explicitly override this per-scan dynamically during uploads if needed.")
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("Geoprivacy")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func selectGeoprivacy(_ value: String) {
        // Haptic feedback
        HapticManager.shared.triggerSelectionPulse()
        defaultGeoprivacy = value
        onGeoprivacyChanged(value)
        dismiss()
    }
}

private struct GeoprivacyOptionRow: View {
    let title: String
    let description: String
    let systemImage: String
    let iconColor: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundColor(iconColor)
                    .frame(width: 32, alignment: .center)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title3)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
