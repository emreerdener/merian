import SwiftUI

enum ComplimentaryPlanDetailContext {
    case hidden
    case results
    case settings

    var showsDetails: Bool {
        self != .hidden
    }
}

struct PlanCard: View {
    @Environment(RevenueCatManager.self) var revenueCat
    @Binding var showPaywall: Bool
    var complimentaryDetailContext: ComplimentaryPlanDetailContext = .hidden
    @State private var entitlement = EntitlementManager.shared

    private var hasComplimentaryPro: Bool {
        !revenueCat.isSubscribed && entitlement.hasVerifiedComplimentaryAccess
    }

    private var planTitle: String {
        if revenueCat.isSubscribed { return "Pro" }
        if hasComplimentaryPro { return "Complimentary Pro" }
        return "Free"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: revenueCat.isProActive ? "lock.open.fill" : "lock.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .semibold))
                        Text(revenueCat.isSubscribed ? "HIGH-VOLUME SCANS" : (hasComplimentaryPro ? "COMPLIMENTARY PRO" : "1 FLASH SCAN DAILY"))
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }
                    
                    Text(planTitle)
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
            
            Text(planSummary)
                .font(.system(.subheadline))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
            Button(action: {
                if revenueCat.isSubscribed {
                    revenueCat.showManageSubscriptions()
                } else {
                    showPaywall = true
                }
            }) {
                HStack {
                    Image(systemName: revenueCat.isSubscribed ? "gearshape" : "arrow.up.circle")
                        .font(.system(size: 20, weight: .semibold))
                    Text(revenueCat.isSubscribed ? "Manage plan" : "Upgrade to Pro")
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

    private var planSummary: String {
        if revenueCat.isSubscribed {
            return ProPlanValueProps.activePlanSummary
        }
        if complimentaryDetailContext.showsDetails && hasComplimentaryPro {
            return "\(entitlement.scansRemaining) of 3 complimentary Pro scans remain. Your separate daily Flash scan stays available."
        }
        if complimentaryDetailContext.showsDetails && entitlement.isComplimentaryExhausted {
            return "All 3 complimentary Pro scans have been used. Saved Pro results remain available, and your daily Flash scan continues."
        }
        return ProPlanValueProps.upgradePlanSummary
    }
}
