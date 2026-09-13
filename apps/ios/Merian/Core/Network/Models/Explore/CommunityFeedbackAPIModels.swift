import Foundation
import UIKit

struct CommunityFeedbackSubmission: Encodable {
    let feedback: String
    let appVersion: String
    let buildNumber: String
    let platform: String
    let osVersion: String

    enum CodingKeys: String, CodingKey {
        case feedback
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case osVersion = "os_version"
    }

    init(feedback: String) {
        self.feedback = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        self.platform = "ios"
        self.osVersion = UIDevice.current.systemVersion
    }
}
