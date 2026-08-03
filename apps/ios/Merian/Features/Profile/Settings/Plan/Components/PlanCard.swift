import SwiftUI

enum ComplimentaryScanDisplayState: Equatable {
    case available(scansRemaining: Int)
    case exhausted

    var scansRemaining: Int {
        switch self {
        case .available(let scansRemaining):
            scansRemaining
        case .exhausted:
            0
        }
    }

    var hasAccess: Bool {
        switch self {
        case .available:
            true
        case .exhausted:
            false
        }
    }

    var isExhausted: Bool {
        self == .exhausted
    }
}

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
    var complimentaryDisplayOverride: ComplimentaryScanDisplayState?
    @State private var entitlement = EntitlementManager.shared

    private var isSubscribed: Bool {
        complimentaryDisplayOverride == nil && revenueCat.isSubscribed
    }

    private var isProActive: Bool {
        if let complimentaryDisplayOverride {
            return complimentaryDisplayOverride.hasAccess
        }
        return revenueCat.isProActive
    }

    private var hasComplimentaryPro: Bool {
        if let complimentaryDisplayOverride {
            return complimentaryDisplayOverride.hasAccess
        }
        return !revenueCat.isSubscribed && entitlement.hasVerifiedComplimentaryAccess
    }

    private var scansRemaining: Int {
        complimentaryDisplayOverride?.scansRemaining ?? entitlement.scansRemaining
    }

    private var isComplimentaryExhausted: Bool {
        complimentaryDisplayOverride?.isExhausted ?? entitlement.isComplimentaryExhausted
    }

    private var planTitle: String {
        if isSubscribed { return "Pro" }
        if hasComplimentaryPro { return "Complimentary Pro" }
        return "Free"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: isProActive ? "lock.open.fill" : "lock.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 14, weight: .semibold))
                        Text(isSubscribed ? "HIGH-VOLUME SCANS" : (hasComplimentaryPro ? "COMPLIMENTARY PRO" : "1 FLASH SCAN DAILY"))
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
                
                if isProActive {
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
                if isSubscribed {
                    revenueCat.showManageSubscriptions()
                } else {
                    showPaywall = true
                }
            }) {
                HStack {
                    Image(systemName: isSubscribed ? "gearshape" : "arrow.up.circle")
                        .font(.system(size: 20, weight: .semibold))
                    Text(isSubscribed ? "Manage plan" : "Upgrade to Pro")
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
        if isSubscribed {
            return ProPlanValueProps.activePlanSummary
        }
        if complimentaryDetailContext.showsDetails && hasComplimentaryPro {
            return "\(scansRemaining) of 3 complimentary Pro scans remain. Your separate daily Flash scan stays available."
        }
        if complimentaryDetailContext.showsDetails && isComplimentaryExhausted {
            return "All 3 complimentary Pro scans have been used. Saved Pro results remain available, and your daily Flash scan continues."
        }
        return ProPlanValueProps.upgradePlanSummary
    }
}
