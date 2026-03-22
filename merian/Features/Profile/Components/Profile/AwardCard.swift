import SwiftUI

// MARK: - Individual Gamification Unit
struct AwardCard: View {
    let award: AwardPayload
    
    private var difficultyColor: Color {
        switch award.difficultyLevel {
        case 2: return Color(red: 0.85, green: 0.3, blue: 0.3) // Hard (Crimson)
        case 1: return Color(red: 0.9, green: 0.6, blue: 0.1) // Medium (Amber)
        default: return Color(red: 0.25, green: 0.75, blue: 0.35) // Easy (Spring Green)
        }
    }
    
    private var tintInfo: (color: Color, icon: String) {
        switch award.type.lowercased() {
        case "first_scan": return (Color(red: 0.25, green: 0.75, blue: 0.35), "shoeprints.fill") // Bright Spring Green matching the mockup
        case "explorer": return (Color(red: 0.8, green: 0.6, blue: 0.2), "safari.fill") // Golden/Yellow for exploration
        case "fungi": return (Color(red: 0.6, green: 0.4, blue: 0.6), "camera.macro") // Soft Mauve/Purple for Fungi
        case "plantae": return (Color(red: 0.3, green: 0.6, blue: 0.3), "leaf.fill") // Deep Forest Green for Plants
        case "insecta": return (Color(red: 0.8, green: 0.4, blue: 0.3), "ant.fill") // Rust/Orange for Bugs
        case "urban": return (Color(red: 0.4, green: 0.5, blue: 0.7), "building.2.fill") // Slate Blue for Urban/Domesticated
        
        case "frost_walker": return (Color(red: 0.4, green: 0.7, blue: 0.9), "snowflake")
        case "alpine": return (Color(red: 0.6, green: 0.6, blue: 0.7), "mountain.2.fill")
        case "nocturnal": return (Color(red: 0.3, green: 0.2, blue: 0.6), "moon.stars.fill") // Deep Purple
        case "guardian": return (Color(red: 0.85, green: 0.3, blue: 0.3), "shield.lefthalf.filled")
        case "conservationist": return (Color(red: 0.2, green: 0.6, blue: 0.5), "globe.americas.fill")
        case "toxicologist": return (Color(red: 0.75, green: 0.8, blue: 0.1), "exclamationmark.triangle.fill")
        case "perfect_lens": return (Color(red: 0.3, green: 0.5, blue: 0.9), "scope")
        
        default: return (Color.gray, "star.fill")
        }
    }
    
    private var descriptionText: String {
        switch award.type.lowercased() {
        case "first_scan": return "Complete your first nature scan"
        case "explorer": return "Scan \(award.targetCount) different species"
        case "fungi": return "Scan \(award.targetCount) different fungi species"
        case "plantae": return "Scan \(award.targetCount) different plant species"
        case "insecta": return "Scan \(award.targetCount) different animal species"
        case "urban": return "Scan \(award.targetCount) species in urban environments"
        
        case "frost_walker": return "Scan \(award.targetCount) active species in freezing temperatures"
        case "alpine": return "Document \(award.targetCount) species at extreme altitudes"
        case "nocturnal": return "Identify \(award.targetCount) species strictly after dark"
        case "guardian": return "Identify \(award.targetCount) known invasive species"
        case "conservationist": return "Document a rare species protected by the IUCN Red List"
        case "toxicologist": return "Safely identify \(award.targetCount) highly toxic plants or fungi"
        case "perfect_lens": return "Capture \(award.targetCount) perfect photos (98%+ AI Confidence)"
        
        default: return "Complete this ecological milestone"
        }
    }
    
    private var formattedTitle: String {
        guard let first = award.title.first else { return award.title }
        return String(first).uppercased() + award.title.dropFirst().lowercased()
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // MARK: - Premium Iconography Layout
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(award.isCompleted ? tintInfo.color.opacity(0.12) : Color(uiColor: .systemGray6))
                    .frame(width: 48, height: 48)
                
                Image(systemName: tintInfo.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundColor(award.isCompleted ? tintInfo.color : Color(uiColor: .systemGray))
            }
            
            // MARK: - Structural Text & Progress Metrics
            VStack(alignment: .leading, spacing: 5) {
                // Header row: Title + Difficulty Pill
                HStack(alignment: .center) {
                    Text(formattedTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                    
                    Spacer()
                    
                    Text(award.difficultyString)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(difficultyColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(difficultyColor.opacity(0.12))
                        )
                }
                
                // Description row
                Text(descriptionText)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 4)
                
                if award.isCompleted {
                    // Completed Badge
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Completed")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(Color(red: 0.25, green: 0.75, blue: 0.35))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 0.25, green: 0.75, blue: 0.35).opacity(0.12))
                    )
                    .padding(.top, 4)
                } else {
                    // Progress Label Row
                    HStack {
                        Text("Progress: \(award.currentCount)/\(award.targetCount)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.primary.opacity(0.4))
                        
                        Spacer()
                    }
                    
                    // Custom Fluid Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color(uiColor: .systemGray6))
                                .frame(height: 5)
                            
                            Capsule()
                                .fill(Color(red: 0.25, green: 0.75, blue: 0.35).opacity(0.8))
                                .frame(width: max(0, geo.size.width * award.progressFraction), height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 2)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
        )
    }
}
