import RevenueCat
import SwiftUI

struct PaywallHeroSlide: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let subtitle: String
    let glowColor: Color
}

struct PaywallFeatureComparison: Identifiable {
    let id = UUID()
    let title: String
    let freeValue: String
    let proValue: String
}

struct PaywallReview: Identifiable {
    let id = UUID()
    let title: String
    let rating: Int
    let body: String
    let author: String
}

enum ProPlanValueProps {
    static let activePlanSummary = "You have high-volume field scans, Pro AI vision, video scans, AI chat, multi-capture, Apple Watch logging, and expedition mode unlocked."
    static let upgradePlanSummary = "You have 1 free scan daily. Upgrade for high-volume field scans, Pro AI vision, video scans, AI chat, multi-capture, Apple Watch logging, and expedition mode."

    static let featuredSlides = [
        PaywallHeroSlide(
            imageName: "luna-moth",
            title: "High-volume field scans",
            subtitle: "Keep identifying with generous fair-use capacity.",
            glowColor: .mint
        ),
        PaywallHeroSlide(
            imageName: "hawk",
            title: "Advanced AI analysis",
            subtitle: "Use Naturebook's most capable model for deeper analysis.",
            glowColor: .orange
        ),
        PaywallHeroSlide(
            imageName: "camera-lens",
            title: "Video scans",
            subtitle: "Record video clips for richer identification context.",
            glowColor: .purple
        ),
        PaywallHeroSlide(
            imageName: "blue-bird",
            title: "Multi-capture analysis",
            subtitle: "Add multiple scans to a single analysis.",
            glowColor: .cyan
        ),
        PaywallHeroSlide(
            imageName: "bee",
            title: "Expedition mode",
            subtitle: "Maximize battery life and performance out in the field.",
            glowColor: .green
        )
    ]

    static let comparisons = [
        PaywallFeatureComparison(
            title: "Daily scans",
            freeValue: "1",
            proValue: "High-volume"
        ),
        PaywallFeatureComparison(
            title: "AI model",
            freeValue: "Flash",
            proValue: "Pro"
        ),
        PaywallFeatureComparison(
            title: "Video scans",
            freeValue: "-",
            proValue: "Included"
        ),
        PaywallFeatureComparison(
            title: "AI chat",
            freeValue: "-",
            proValue: "Included"
        ),
        PaywallFeatureComparison(
            title: "Multi-capture",
            freeValue: "-",
            proValue: "Included"
        ),
        PaywallFeatureComparison(
            title: "Apple Watch logging",
            freeValue: "-",
            proValue: "Included"
        ),
        PaywallFeatureComparison(
            title: "Group events",
            freeValue: "Join only",
            proValue: "Host"
        ),
        PaywallFeatureComparison(
            title: "Expedition mode",
            freeValue: "-",
            proValue: "Included"
        )
    ]

    static let reviews = [
        PaywallReview(
            title: "Essential field tool",
            rating: 5,
            body: "Naturebook Pro has completely transformed my weekend hikes. The expedition mode saves so much battery, and the Pro AI offline capabilities are insanely accurate.",
            author: "ForestPathfinder"
        ),
        PaywallReview(
            title: "Stunning UI & details",
            rating: 5,
            body: "The depth of local ecological information inside the Pro insight cards is exceptional. Highly recommend it to anyone wanting to learn more about the outdoors.",
            author: "EcoExplorer"
        ),
        PaywallReview(
            title: "Absolutely worth it",
            rating: 5,
            body: "The generous scan capacity is a must! I take dozens of pictures of mosses and lichens during fieldwork and the app never misses a beat. Essential for my job.",
            author: "BioResearcher"
        )
    ]
}

enum PaywallFixedPlanDisplay {
    static let sevenDayPassPrice = "$3.99"
    static let annualPrice = "$24.99"
    static let annualProductIdentifier =
        RevenueCatOfferingPolicy.annualProductIdentifier
}

extension Package {
    var isAnnualPlan: Bool {
        packageType == .annual ||
            storeProduct.productIdentifier ==
                PaywallFixedPlanDisplay.annualProductIdentifier
    }

    var isSevenDayPassPlan: Bool {
        if packageType == .weekly ||
            storeProduct.productIdentifier ==
                SevenDayPassAccessPolicy.productIdentifier {
            return true
        }

        let searchableText = [
            identifier,
            storeProduct.productIdentifier,
            storeProduct.localizedTitle,
            storeProduct.localizedDescription
        ]
        .joined(separator: " ")
        .lowercased()

        return searchableText.contains("7 day") ||
            searchableText.contains("7-day") ||
            searchableText.contains("seven day") ||
            searchableText.contains("7_day") ||
            (searchableText.contains("7") && searchableText.contains("pass"))
    }

    var paywallDisplayPrice: String {
        if isSevenDayPassPlan {
            return PaywallFixedPlanDisplay.sevenDayPassPrice
        }
        if isAnnualPlan {
            return PaywallFixedPlanDisplay.annualPrice
        }
        return storeProduct.localizedPriceString
    }

    var paywallSortRank: Int {
        if isSevenDayPassPlan { return 0 }
        if isAnnualPlan { return 1 }

        switch packageType {
        case .monthly: return 2
        case .lifetime: return 3
        default: return 4
        }
    }
}

enum PaywallPackageSelectionPolicy {
    static func preferredPackage(from packages: [Package]) -> Package? {
        packages.first(where: \.isSevenDayPassPlan) ??
            packages.first(where: \.isAnnualPlan) ??
            packages.first(where: { $0.packageType == .monthly }) ??
            packages.first
    }
}
