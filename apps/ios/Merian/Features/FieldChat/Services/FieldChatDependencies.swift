import Foundation
import UIKit

struct FieldChatDependencies {
    typealias CheckOwnedScanStatus = @MainActor (String) async throws -> String
    typealias Feedback = @MainActor (FieldChatFeedbackEffect) -> Void
    typealias TrackAction = @MainActor (FieldChatSource, FieldChatActionTelemetry) -> Void
    typealias CopyText = @MainActor (String) -> Void
    typealias Now = @MainActor () -> Date
    typealias MakeRequestId = @MainActor () -> String

    let endpoint: FieldChatEndpoint
    let checkOwnedScanStatus: CheckOwnedScanStatus
    let feedback: Feedback
    let trackAction: TrackAction
    let copyText: CopyText
    let now: Now
    let makeRequestId: MakeRequestId

    init(
        endpoint: FieldChatEndpoint,
        checkOwnedScanStatus: @escaping CheckOwnedScanStatus,
        feedback: @escaping Feedback,
        trackAction: @escaping TrackAction,
        copyText: @escaping CopyText,
        now: @escaping Now = Date.init,
        makeRequestId: @escaping MakeRequestId = {
            UUID().uuidString.lowercased()
        }
    ) {
        self.endpoint = endpoint
        self.checkOwnedScanStatus = checkOwnedScanStatus
        self.feedback = feedback
        self.trackAction = trackAction
        self.copyText = copyText
        self.now = now
        self.makeRequestId = makeRequestId
    }
}

extension FieldChatDependencies {
    @MainActor
    static func live(source: FieldChatSource) -> Self {
        let client = MerianNetworkClient.shared
        return FieldChatDependencies(
            endpoint: .live(source: source, client: client),
            checkOwnedScanStatus: {
                try await client.checkScanStatus(scanId: $0)
            },
            feedback: { effect in
                switch effect {
                case .selection:
                    HapticManager.shared.triggerSelectionPulse()
                case .medium:
                    HapticManager.shared.triggerMediumPulse()
                case .success:
                    HapticManager.shared.triggerSuccessPulse()
                case .error:
                    HapticManager.shared.triggerErrorThump()
                }
            },
            trackAction: { source, telemetry in
                if source == .speciesDictionary {
                    AppTelemetry.trackSpeciesDictionaryFieldChatAction(
                        action: telemetry.action,
                        promptCategory: telemetry.promptCategory,
                        isRefusal: telemetry.isRefusal,
                        hasLookalikes: telemetry.hasLookalikes
                    )
                    return
                }

                var properties: [String: Any] = [
                    "action": telemetry.action,
                    "scan_id": telemetry.subjectId,
                    "message_id": telemetry.messageId,
                    "is_refusal": telemetry.isRefusal,
                    "has_lookalikes": telemetry.hasLookalikes,
                    "field_chat_source": source.telemetryValue
                ]
                if let promptCategory = telemetry.promptCategory {
                    properties["prompt_category"] = promptCategory
                }
                PostHogManager.shared.capture(
                    "InsightChatActionTapped",
                    properties: properties
                )
            },
            copyText: { UIPasteboard.general.string = $0 }
        )
    }
}
