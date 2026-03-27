import SwiftUI
import SwiftData
import RevenueCat

struct PremiumInsightsCard: View {
    let habitatDescription: String?
    let globalDistributionRegions: [String]?
    let scientificName: String?
    let scanId: String?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceEngine.self) private var inferenceEngine
    
    @State private var isUnlocking = false
    @State private var unlockError: String? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.yellow)
                    .frame(width: 28, height: 28)
                    .background(Color.yellow.opacity(0.15))
                    .clipShape(Circle())
                
                Text("Premium Insights")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal)
            
            if let habitat = habitatDescription {
                // UNLOCKED STATE
                VStack(alignment: .leading, spacing: 12) {
                    Text("Habitat & Distribution")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    Text(habitat)
                        .font(.body)
                        .lineSpacing(4)
                    
                    if let regions = globalDistributionRegions, !regions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(regions, id: \.self) { region in
                                    Text(region)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .foregroundStyle(Color.accentColor)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal)
                
            } else {
                // PAYWALL STATE
                VStack(spacing: 16) {
                    Text("Unlock deep ecology insights for this scan and everything else you find this week for $2.99.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    
                    if let error = unlockError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    
                    Button(action: {
                        Task { await unlockInsights() }
                    }) {
                        HStack {
                            if isUnlocking {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(RevenueCatManager.shared.isProActive ? "Generate Insights" : "Unlock 7-Day Pass - $2.99")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background {
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .clipShape(Capsule())
                    }
                    .disabled(isUnlocking)
                }
                .padding(.vertical, 24)
                .padding(.horizontal)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                .padding(.horizontal)
            }
        }
    }
    
    @MainActor
    private func unlockInsights() async {
        guard let sciName = scientificName, let sid = scanId else { return }
        
        isUnlocking = true
        unlockError = nil
        defer { isUnlocking = false }
        
        do {
            // 1. Purchase if not Pro
            if !RevenueCatManager.shared.isProActive {
                if let currentOffering = RevenueCatManager.shared.currentOfferings?.current,
                   let pkg = currentOffering.weekly ?? currentOffering.availablePackages.first(where: { $0.storeProduct.productIdentifier.contains("7_day_pass") || $0.storeProduct.productIdentifier.contains("weekly") }) {
                    try await RevenueCatManager.shared.purchase(pkg)
                } else {
                    unlockError = "7-Day Pass not found in current offerings. Please ensure a Weekly package is configured in RevenueCat."
                    return
                }
            }
            
            // 2. Call edge function
            struct Payload: Encodable {
                let scan_id: String
                let scientific_name: String
            }
            
            struct ResponseData: Decodable {
                let success: Bool?
                let data: PremiumData?
                struct PremiumData: Decodable {
                    let habitat_description: String?
                    let global_distribution_regions: [String]?
                }
            }
            
            let res: ResponseData = try await SupabaseManager.shared.client.functions.invoke(
                "enrich-scan",
                options: .init(body: Payload(scan_id: sid, scientific_name: sciName))
            )
            
            guard let premiumData = res.data else {
                unlockError = "Failed to generate AI insights."
                return
            }
            
            // 3. Update active context state
            inferenceEngine.speciesData?.habitatDescription = premiumData.habitat_description
            inferenceEngine.speciesData?.globalDistributionRegions = premiumData.global_distribution_regions
            
            // 4. Update SwiftData record
            var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { $0.id == sid })
            descriptor.fetchLimit = 1
            if let record = try? modelContext.fetch(descriptor).first {
                record.habitatDescription = premiumData.habitat_description
                if let dist = premiumData.global_distribution_regions, let encoded = try? JSONEncoder().encode(dist) {
                    record.globalDistributionRegionsJson = String(data: encoded, encoding: .utf8)
                }
                try? modelContext.save()
            }
            HapticManager.shared.triggerSuccessPulse()
            
        } catch {
            unlockError = error.localizedDescription
            MerianLog.general.error("Failed to unlock insights: \(error, privacy: .private)")
            HapticManager.shared.triggerErrorThump()
        }
    }
}
