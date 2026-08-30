import Foundation
import UIKit

@MainActor
struct DescribePresentationDependencies {
    let tagFrequency: @MainActor (_ tagId: String) -> Int
    let recordTagUsage: @MainActor (_ tagId: String) -> Void
    let selectionFeedback: @MainActor () -> Void
    let dismissKeyboard: @MainActor () -> Void

    static var live: Self {
        let tagUsage = DescribeTagUsageStore(defaults: .standard)
        return Self(
            tagFrequency: { tagUsage.frequency(for: $0) },
            recordTagUsage: { tagUsage.recordUsage(for: $0) },
            selectionFeedback: {
                HapticManager.shared.triggerSelectionPulse()
            },
            dismissKeyboard: {
                UIApplication.shared.sendAction(
                    #selector(UIResponder.resignFirstResponder),
                    to: nil,
                    from: nil,
                    for: nil
                )
            }
        )
    }
}

@MainActor
private struct DescribeTagUsageStore {
    private let defaults: UserDefaults
    private let keyPrefix = "DescribeTagFreq_"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func frequency(for tagId: String) -> Int {
        defaults.integer(forKey: keyPrefix + tagId)
    }

    func recordUsage(for tagId: String) {
        defaults.set(frequency(for: tagId) + 1, forKey: keyPrefix + tagId)
    }
}
