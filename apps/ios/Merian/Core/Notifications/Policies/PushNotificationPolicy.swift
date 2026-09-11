import Foundation

enum PushNotificationPolicy {
    static func encodedDeviceToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func registrationRequest(
        accountScopeID: String?,
        deviceToken: String?,
        environment: String,
        hasAuthorization: Bool,
        exploreEnabled: Bool,
        commentMentionsEnabled: Bool,
        communityIdentificationsEnabled: Bool
    ) -> PushRegistrationRequest? {
        guard let deviceToken, !deviceToken.isEmpty else { return nil }
        return PushRegistrationRequest(
            accountScopeID: accountScopeID,
            deviceToken: deviceToken,
            environment: environment,
            exploreEnabled: hasAuthorization && exploreEnabled,
            commentMentionsEnabled: hasAuthorization && commentMentionsEnabled,
            communityIdentificationsEnabled:
                hasAuthorization && communityIdentificationsEnabled
        )
    }

    static func route(
        userInfo: [AnyHashable: Any],
        isDismissAction: Bool
    ) -> AppRoute? {
        guard !isDismissAction else { return nil }

        if userInfo["type"] as? String == "explore_activity" {
            let requestID = (userInfo["communityRequestId"] as? String)
                ?? (userInfo["community_request_id"] as? String)
            if let requestID {
                return .communityIdentification(requestId: requestID)
            }

            guard let postID = userInfo["postId"] as? String else {
                return nil
            }
            let commentID = (userInfo["commentId"] as? String)
                ?? (userInfo["comment_id"] as? String)
            let parentCommentID =
                (userInfo["parentCommentId"] as? String)
                ?? (userInfo["parent_comment_id"] as? String)
            return .explorePost(
                postId: postID,
                targetCommentId: commentID,
                targetReplyParentCommentId: parentCommentID
            )
        }

        guard let scanID = userInfo["scanId"] as? String else { return nil }
        return .scan(scanId: scanID)
    }

    static func foregroundPresentation(
        notificationType: String?,
        suppressesInferenceBanners: Bool
    ) -> PushForegroundPresentation {
        if notificationType == "explore_activity" {
            return .bannerSoundAndList
        }
        if notificationType == "achievement" || suppressesInferenceBanners {
            return .silent
        }
        return .bannerSoundAndList
    }

    static func inferenceCompleteDescriptor(
        speciesName: String,
        scanID: String,
        imageURL: URL?
    ) -> LocalNotificationDescriptor {
        LocalNotificationDescriptor(
            identifier: "inference_\(scanID)",
            title: speciesName,
            body: "Analysis complete. Tap to view full insights.",
            userInfo: ["scanId": scanID],
            categoryIdentifier: PushNotificationIdentifiers.inferenceCategory,
            threadIdentifier: PushNotificationIdentifiers.inferenceThread,
            isTimeSensitive: true,
            attachmentURL: imageURL
        )
    }

    static func uploadFailedDescriptor(
        identifier: String
    ) -> LocalNotificationDescriptor {
        LocalNotificationDescriptor(
            identifier: identifier,
            title: "Upload failed",
            body: "A background scan was unable to upload and has been discarded.",
            userInfo: ["type": "failure"],
            categoryIdentifier: nil,
            threadIdentifier: nil,
            isTimeSensitive: false,
            attachmentURL: nil
        )
    }

    static func achievementDescriptor(
        title: String,
        identifier: String
    ) -> LocalNotificationDescriptor {
        LocalNotificationDescriptor(
            identifier: identifier,
            title: "Achievement Unlocked!",
            body: "You just earned: \(title)",
            userInfo: ["type": "achievement"],
            categoryIdentifier: nil,
            threadIdentifier: nil,
            isTimeSensitive: false,
            attachmentURL: nil
        )
    }
}
