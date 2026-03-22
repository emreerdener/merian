import SwiftUI

struct ConfidenceExplanationSheet: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 32) {
                // MARK: - Vibrant Header
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("AI confidence")
                            .font(.system(.title, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text("Merian leverages dynamic computer vision to resolve taxonomies. This spectrum represents the exact boundaries of the algorithm.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .lineSpacing(4)
                    }
                }
                
                // MARK: - Continuous Spectrum Timeline
                VStack(spacing: 0) {
                    SpectrumNode(
                        color: Color(red: 0.11, green: 0.52, blue: 0.28),
                        nextColor: Color(red: 0.11, green: 0.52, blue: 0.28),
                        percentage: "95% - 100%",
                        title: "High confidence",
                        description: "Extremely certain. The key visual structures match the model flawlessly."
                    )
                    
                    SpectrumNode(
                        color: Color(red: 0.11, green: 0.52, blue: 0.28),
                        nextColor: .orange,
                        percentage: "85% - 94%",
                        title: "Confident",
                        description: "Highly probable. Traits align perfectly with standard species morphology."
                    )
                    
                    SpectrumNode(
                        color: .orange,
                        nextColor: .red,
                        percentage: "70% - 84%",
                        title: "Educated guess",
                        description: "A likely match, but key identifying traits may be obscured, blurry, or missing."
                    )
                    
                    SpectrumNode(
                        color: .red,
                        nextColor: nil,
                        percentage: "Below 70%",
                        title: "Low confidence",
                        description: "The model is uncertain. Try capturing another angle or bringing it into focus."
                    )
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemFill).opacity(0.5)) // Ambient Glass Card Housing
                        .overlay(
                            RoundedRectangle(cornerRadius: 32, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1) // Structural Glare Line
                        )
                )
                .padding(.horizontal, 16)
                
                // MARK: - Pro Tips
                VStack(alignment: .leading, spacing: 20) {
                    Text("How to improve accuracy")
                        .font(.system(.title3, weight: .bold))
                        .foregroundColor(.primary)
                    
                    VStack(alignment: .leading, spacing: 16) {
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
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
    }
}

// MARK: - Seamless Gradient Node
struct SpectrumNode: View {
    let color: Color
    let nextColor: Color?
    let percentage: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            
            // 1. The Continuous Vertical Axis
            VStack(spacing: 0) {
                // The Node Dot Core
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                }
                
                // The connecting stroke stretches physically filling exactly to the next Node bounds!
                if let next = nextColor {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.6), next.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3)
                }
            }
            // Lock axis width to guarantee pixel-perfect geometric centering
            .frame(width: 32)
            
            // 2. The Semantic Label Payload
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(percentage)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundColor(color.opacity(0.8))
                        
                    Text(title)
                        .font(.system(.title3, weight: .bold))
                        .foregroundColor(color)
                }
                
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(4)
            }
            .padding(.top, 4) // Optically aligns text header dynamically down into the Circle origin mathematically
            .padding(.bottom, nextColor != nil ? 32 : 0) // Elongates vertical boundary spanning the connection path natively!
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Tip Row
struct TipRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
