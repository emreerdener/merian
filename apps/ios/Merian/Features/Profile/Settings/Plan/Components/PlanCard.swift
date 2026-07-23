import SwiftUI

struct PlanCard: View {
    @Environment(RevenueCatManager.self) var revenueCat
    @Binding var showPaywall: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: revenueCat.isProActive ? "lock.open.fill" : "lock.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .semibold))
                        Text(revenueCat.isProActive ? "HIGH-VOLUME SCANS" : "1 SCAN DAILY")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }
                    
                    Text(revenueCat.isProActive ? "Pro" : "Free")
                        .font(.system(.title, design: .serif))
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if revenueCat.isProActive {
                    Image("luna-moth")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)
                } else {
                    Image("compass")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 56, height: 56)     
                }
            }
            
            Text(revenueCat.isProActive ? ProPlanValueProps.activePlanSummary : ProPlanValueProps.upgradePlanSummary)
                .font(.system(.subheadline))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
            Button(action: {
                if revenueCat.isProActive {
                    revenueCat.showManageSubscriptions()
                } else {
                    showPaywall = true
                }
            }) {
                HStack {
                    Image(systemName: revenueCat.isProActive ? "gearshape" : "arrow.up.circle")
                        .font(.system(size: 20, weight: .semibold))
                    Text(revenueCat.isProActive ? "Manage plan" : "Upgrade to Pro")
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.primary)
                .foregroundColor(Color(UIColor.systemBackground))
                .clipShape(Capsule())
            }
            .padding(.top, 8)
            .buttonStyle(BorderlessButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
