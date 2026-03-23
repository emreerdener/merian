import SwiftUI

struct ProTips: View {
    let showLocationPrompt: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How to improve accuracy")
                .font(.system(.title3, weight: .bold))
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 16) {
                if showLocationPrompt {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(Color.purple.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.purple)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable location data")
                                    .font(.system(.subheadline, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                Text("Inject local topology and weather telemetry directly into the AI for max accuracy.")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(2)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Color(uiColor: .tertiaryLabel))
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .opacity(0.5)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                }
                
                TipRow(
                    icon: "camera.macro",
                    color: .blue,
                    title: "Fill the frame",
                    description: "Get closer to your subject so it completely dominates the composition."
                )
                
                TipRow(
                    icon: "sun.max",
                    color: .orange,
                    title: "Seek clear lighting",
                    description: "Avoid harsh shadows, extreme backlighting, or heavy motion blur."
                )
                
                TipRow(
                    icon: "viewfinder.rectangular",
                    color: .green,
                    title: "Focus on key traits",
                    description: "Ensure defining structures like leaves, bark, or wings are sharply in focus."
                )
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(uiColor: .secondarySystemFill).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
    }
}
