import SwiftUI

struct PlanCard: View {
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
                        .foregroundColor(.secondary.opacity(0.5))
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
            .buttonStyle(BorderlessButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.04), radius: 8, y: 4)
    }
}
