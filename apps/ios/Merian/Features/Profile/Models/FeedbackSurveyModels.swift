import Foundation
import UIKit

enum FeedbackSurveyCampaign {
    static let currentId = "beta_feedback_2026_06"
    static let meaningfulCompletedScanCount = 3
    static let repeatSubmissionCooldown: TimeInterval = 24 * 60 * 60

    static func isSubmittedStateActive(
        campaignId: String = currentId,
        submittedCampaignId: String,
        submittedAt: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard submittedCampaignId == campaignId, submittedAt > 0 else { return false }
        return now.timeIntervalSince1970 - submittedAt < repeatSubmissionCooldown
    }
}

enum FeedbackSurveyFeatureUse: String, CaseIterable, Identifiable, Codable {
    case identifyFoundSubject = "identify_found_subject"
    case learnAfterScan = "learn_after_scan"
    case buildCollection = "build_collection"
    case shareToExplore = "share_to_explore"
    case browseExplore = "browse_explore"
    case audioOrDescription = "audio_or_description"
    case other = "other"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .identifyFoundSubject:
            return "Identify something I found"
        case .learnAfterScan:
            return "Learn more after a scan"
        case .buildCollection:
            return "Build my collection"
        case .shareToExplore:
            return "Share to Explore"
        case .browseExplore:
            return "Browse Explore"
        case .audioOrDescription:
            return "Audio or description capture"
        case .other:
            return "Other"
        }
    }
}

enum FeedbackSurveyUsefulFeature: String, CaseIterable, Identifiable, Codable {
    case cameraIdentification = "camera_identification"
    case insightSheet = "insight_sheet"
    case speciesDictionary = "species_dictionary"
    case scanLibraryCollections = "scan_library_collections"
    case explore = "explore"
    case profileProgress = "profile_progress"
    case notSureYet = "not_sure_yet"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cameraIdentification:
            return "Camera identification"
        case .insightSheet:
            return "Insight sheet"
        case .speciesDictionary:
            return "Species dictionary"
        case .scanLibraryCollections:
            return "Scan library and collections"
        case .explore:
            return "Explore"
        case .profileProgress:
            return "Profile and progress"
        case .notSureYet:
            return "Not sure yet"
        }
    }
}

enum FeedbackSurveyBugStatus: String, CaseIterable, Identifiable, Codable {
    case no
    case workaround
    case blocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .no:
            return "No"
        case .workaround:
            return "Yes, but I worked around it"
        case .blocked:
            return "Yes, and it blocked me"
        }
    }

    var detail: String {
        switch self {
        case .no:
            return "I have not run into bugs or crashes."
        case .workaround:
            return "Something went wrong, but I was still able to keep going."
        case .blocked:
            return "A bug, crash, or error stopped me from finishing what I wanted to do."
        }
    }
}

struct FeedbackSurveyPromptPolicy {
    static func shouldPrompt(
        campaignId: String = FeedbackSurveyCampaign.currentId,
        completedScanCount: Int,
        hasCompletedOnboarding: Bool,
        dismissedCampaignId: String,
        submittedCampaignId: String
    ) -> Bool {
        guard hasCompletedOnboarding else { return false }
        guard completedScanCount >= FeedbackSurveyCampaign.meaningfulCompletedScanCount else { return false }
        guard dismissedCampaignId != campaignId else { return false }
        guard submittedCampaignId != campaignId else { return false }
        return true
    }
}

struct FeedbackSurveySubmission: Encodable {
    let surveyCampaignId: String
    let satisfactionRating: Int
    let recommendationRating: Int
    let usedFeatures: [FeedbackSurveyFeatureUse]
    let mostUsefulFeatures: [FeedbackSurveyUsefulFeature]
    let confusingOrDisappointing: String
    let wishedNext: String
    let bugStatus: FeedbackSurveyBugStatus
    let bugDetails: String
    let mayFollowUp: Bool
    let contact: String
    let appVersion: String
    let buildNumber: String
    let platform: String
    let deviceModel: String
    let osVersion: String
    let locale: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case surveyCampaignId = "survey_campaign_id"
        case satisfactionRating = "satisfaction_rating"
        case recommendationRating = "recommendation_rating"
        case usedFeatures = "used_features"
        case mostUsefulFeatures = "most_useful_features"
        case confusingOrDisappointing = "confusing_or_disappointing"
        case wishedNext = "wished_next"
        case bugStatus = "bug_status"
        case bugDetails = "bug_details"
        case mayFollowUp = "may_follow_up"
        case contact
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case platform
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case locale
        case timezone
    }

    init(
        surveyCampaignId: String = FeedbackSurveyCampaign.currentId,
        satisfactionRating: Int,
        recommendationRating: Int,
        usedFeatures: [FeedbackSurveyFeatureUse],
        mostUsefulFeatures: [FeedbackSurveyUsefulFeature],
        confusingOrDisappointing: String,
        wishedNext: String,
        bugStatus: FeedbackSurveyBugStatus,
        bugDetails: String,
        mayFollowUp: Bool,
        contact: String
    ) {
        self.surveyCampaignId = surveyCampaignId
        self.satisfactionRating = satisfactionRating
        self.recommendationRating = recommendationRating
        self.usedFeatures = usedFeatures
        self.mostUsefulFeatures = mostUsefulFeatures
        self.confusingOrDisappointing = confusingOrDisappointing.trimmingCharacters(in: .whitespacesAndNewlines)
        self.wishedNext = wishedNext.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bugStatus = bugStatus
        self.bugDetails = bugDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mayFollowUp = mayFollowUp
        self.contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        self.platform = "ios"
        self.deviceModel = UIDevice.current.model
        self.osVersion = UIDevice.current.systemVersion
        self.locale = Locale.current.identifier
        self.timezone = TimeZone.current.identifier
    }
}
