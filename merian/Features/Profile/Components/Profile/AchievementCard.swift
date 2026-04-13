import SwiftUI

// MARK: - Individual Gamification Unit
struct AchievementCard: View {
    let award: AwardPayload
    
    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            AchievementIconView(award: award)
            AchievementMetricsView(award: award)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Extracted Subcomponents
private struct AchievementIconView: View {
    let award: AwardPayload
    
    // Core animation state for the premium specular border glow
    @State private var shimmerPhase: CGFloat = -1.0
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(award.isCompleted ? award.tintInfo.color.opacity(0.12) : Color(uiColor: .systemGray6))
                .frame(width: 80, height: 80)
            
            Image(award.tintInfo.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .grayscale(award.isCompleted ? 0 : 1.0)
                .opacity(award.isCompleted ? 1.0 : 0.4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(award.isCompleted ? award.tintInfo.color.opacity(0.25) : Color.primary.opacity(0.08), lineWidth: 1.5)
        )
        .overlay(
            Group {
                if award.isCompleted {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: award.tintInfo.color, location: 0.5),
                                        .init(color: .clear, location: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: max(geo.size.width, 1))
                            .offset(x: shimmerPhase * max(geo.size.width, 1) * 2)
                            .blendMode(.screen)
                            .mask(
                                RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(lineWidth: 1.5)
                            )
                    }
                }
            }
        )
        .task {
            guard award.isCompleted else { return }
            while !Task.isCancelled {
                let randomSleepSeconds = Double.random(in: 4.0...12.0)
                try? await Task.sleep(for: .seconds(randomSleepSeconds))
                
                guard !Task.isCancelled else { break }
                
                shimmerPhase = -1.0
                try? await Task.sleep(nanoseconds: 50_000_000)
                
                withAnimation(.easeOut(duration: 1.8)) {
                    shimmerPhase = 2.5
                }
            }
        }
    }
}

private struct AchievementMetricsView: View {
    let award: AwardPayload
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(award.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary.opacity(0.85))
            
            Text(award.descriptionText)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            
            if award.isCompleted {
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
                AchievementProgressBar(award: award)
            }
        }
    }
}

private struct AchievementProgressBar: View {
    let award: AwardPayload
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Progress: \(award.currentCount)/\(award.targetCount)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.4))
                
                Spacer()
            }
            
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
        }
        .padding(.top, 2)
    }
}

// MARK: - Award Logic Boundary
extension AwardPayload {
    var difficultyColor: Color {
        switch difficultyLevel {
        case 2: return Color(red: 0.85, green: 0.3, blue: 0.3) // Hard (Crimson)
        case 1: return Color(red: 0.9, green: 0.6, blue: 0.1) // Medium (Amber)
        default: return Color(red: 0.25, green: 0.75, blue: 0.35) // Easy (Spring Green)
        }
    }
    
    var tintInfo: (color: Color, imageName: String) {
        switch type.lowercased() {
        case "first_scan": return (Color(red: 0.25, green: 0.75, blue: 0.35), "chick")
        case "explorer": return (Color(red: 0.8, green: 0.6, blue: 0.2), "naturalist")
        case "fungi": return (Color(red: 0.6, green: 0.4, blue: 0.6), "mushroom")
        case "plantae": return (Color(red: 0.3, green: 0.6, blue: 0.3), "leaves")
        case "insecta": return (Color(red: 0.8, green: 0.4, blue: 0.3), "zoo-scene")
        case "urban": return (Color(red: 0.4, green: 0.5, blue: 0.7), "urban")
        case "frost_walker": return (Color(red: 0.4, green: 0.7, blue: 0.9), "snowflake")
        case "alpine": return (Color(red: 0.6, green: 0.6, blue: 0.7), "mountain")
        case "nocturnal": return (Color(red: 0.3, green: 0.2, blue: 0.6), "moon")
        case "guardian": return (Color(red: 0.85, green: 0.3, blue: 0.3), "ivy")
        case "conservationist": return (Color(red: 0.2, green: 0.6, blue: 0.5), "shield")
        case "toxicologist": return (Color(red: 0.75, green: 0.8, blue: 0.1), "toxic")
        case "perfect_lens": return (Color(red: 0.3, green: 0.5, blue: 0.9), "camera-lens")
        default: return (Color.gray, "chick")
        }
    }
    
    var descriptionText: String {
        switch type.lowercased() {
        case "first_scan": return "Complete your first nature scan"
        case "explorer": return "Scan \(targetCount) different species"
        case "fungi": return "Scan \(targetCount) different fungi species"
        case "plantae": return "Scan \(targetCount) different plant species"
        case "insecta": return "Scan \(targetCount) different animal species"
        case "urban": return "Scan \(targetCount) species in urban environments"
        case "frost_walker": return "Scan \(targetCount) active species in freezing temperatures"
        case "alpine": return "Document \(targetCount) species at extreme altitudes"
        case "nocturnal": return "Identify \(targetCount) species strictly after dark"
        case "guardian": return "Identify \(targetCount) known invasive species"
        case "conservationist": return "Document a rare species protected by the IUCN Red List"
        case "toxicologist": return "Safely identify \(targetCount) highly toxic plants or fungi"
        case "perfect_lens": return "Capture \(targetCount) perfect photos (98%+ AI Confidence)"
        default: return "Complete this ecological milestone"
        }
    }
}
