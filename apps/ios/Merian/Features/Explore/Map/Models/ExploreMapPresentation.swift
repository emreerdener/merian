import Foundation

enum ExploreMapPresentation {
    static func discoveriesInViewLabel(
        count: Int,
        usesCompactCount: Bool = false
    ) -> String {
        let formattedCount = usesCompactCount
            ? count.formatted(.number.notation(.compactName))
            : count.formatted()
        let noun = count == 1 ? "discovery" : "discoveries"
        return "\(formattedCount) \(noun) in view"
    }
}
