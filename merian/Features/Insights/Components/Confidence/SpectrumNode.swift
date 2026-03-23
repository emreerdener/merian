import SwiftUI

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
