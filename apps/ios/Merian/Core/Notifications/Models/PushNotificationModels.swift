import Foundation

struct PushRegistrationRequest: Equatable, Sendable {
    /// Internal coalescing identity only. This value is never sent over the
    /// wire; it prevents one account's response from satisfying another's
    /// otherwise-identical registration snapshot.
    let accountScopeID: String?
    let deviceToken: String
    let environment: String
    let exploreEnabled: Bool
    let commentMentionsEnabled: Bool
    let communityIdentificationsEnabled: Bool
}

enum PushForegroundPresentation: Equatable, Sendable {
    case silent
    case bannerSoundAndList
}

struct LocalNotificationDescriptor: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let userInfo: [String: String]
    let categoryIdentifier: String?
    let threadIdentifier: String?
    let isTimeSensitive: Bool
    let attachmentURL: URL?
}

enum PushNotificationIdentifiers {
    static let inferenceCategory = "INFERENCE_COMPLETE"
    static let viewAction = "VIEW_ACTION"
    static let shareAction = "SHARE_ACTION"
    static let inferenceThread = "inference_complete_thread"
}
