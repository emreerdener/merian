import Foundation

/// Stateless JSON construction for the two native Identify request shapes.
/// Endpoint orchestration supplies immutable values; networking stays in the client.
enum InferencePayloadBuilder {
    static func makeContext(
        userId: String,
        telemetry: CaptureTelemetry,
        defaultGeoprivacy: String
    ) -> InferencePayloadContext {
        let captureDate: Date = telemetry.timestamp.flatMap {
            DateUtilities.iso8601Formatter.date(from: $0)
        } ?? Date()

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return InferencePayloadContext(
            userId: userId.lowercased(),
            deviceLocale: Locale.current.language.languageCode?.identifier ?? "en",
            deviceTimeZone: TimeZone.current.identifier,
            deviceRegion: Locale.current.region?.identifier,
            currentMonth: Calendar.current.component(.month, from: captureDate),
            timeOfDay: formatter.string(from: captureDate),
            depthScaleText: telemetry.subjectDistanceInMeters.map {
                String(format: "%.1f meters", $0)
            },
            defaultGeoprivacy: normalizedGeoprivacy(defaultGeoprivacy)
        )
    }

    static func identifyBody(
        r2ObjectKeys: [String]?,
        imageBase64s: [String]?,
        mimeType: String,
        telemetry: CaptureTelemetry,
        context: InferencePayloadContext,
        clientScanId: String?,
        description: String?,
        observationContextJSON: String?
    ) throws -> Data {
        try InferenceMediaPolicy.validatePayloadBudget(
            imageBase64s: imageBase64s ?? [],
            audioBase64s: []
        )

        var payload = telemetryPayloadFields(
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId
        )
        setIfPresent(r2ObjectKeys, forKey: "r2ObjectKeys", in: &payload)
        setIfPresent(imageBase64s, forKey: "imageBase64s", in: &payload)
        payload["mimeType"] = mimeType

        if let description, !description.isEmpty {
            payload["description"] = description
        }

        setIfPresent(
            observationContextObject(from: observationContextJSON),
            forKey: "observation_context",
            in: &payload
        )

        return try jsonData(from: payload)
    }

    static func multimodalBody(
        r2ObjectKeys: [String],
        audioR2ObjectKeys: [String],
        videoR2ObjectKeys: [String] = [],
        imageBase64s: [String],
        audioBase64s: [String],
        videoFrameCount: Int? = nil,
        visualMediaItems: [IdentifyVisualMediaItem]? = nil,
        audioMediaItems: [IdentifyAudioMediaItem]? = nil,
        ownerMediaTimeline: [IdentifyOwnerMediaTimelineItem]? = nil,
        observationContextsJSON: [String],
        mimeType: String,
        telemetry: CaptureTelemetry,
        context: InferencePayloadContext,
        clientScanId: String,
        preferredGoal: FieldTripPreferredGoal? = nil
    ) throws -> Data {
        try InferenceMediaPolicy.validatePayloadBudget(
            imageBase64s: imageBase64s,
            audioBase64s: audioBase64s
        )

        var payload = telemetryPayloadFields(
            telemetry: telemetry,
            context: context,
            clientScanId: clientScanId
        )
        if !r2ObjectKeys.isEmpty {
            payload["r2ObjectKeys"] = r2ObjectKeys
        }
        if !audioR2ObjectKeys.isEmpty {
            payload["audioR2ObjectKeys"] = audioR2ObjectKeys
        }
        if !videoR2ObjectKeys.isEmpty {
            payload["videoR2ObjectKeys"] = videoR2ObjectKeys
        }
        if !imageBase64s.isEmpty {
            payload["imageBase64s"] = imageBase64s
        }
        if !audioBase64s.isEmpty {
            payload["audioBase64s"] = audioBase64s
        }
        if let videoFrameCount, videoFrameCount > 0 {
            payload["videoFrameCount"] = videoFrameCount
        }
        if let visualMediaItems, !visualMediaItems.isEmpty {
            payload["visualMediaItems"] = visualMediaItems.map(\.jsonObject)
        }
        if let audioMediaItems, !audioMediaItems.isEmpty {
            payload["audioMediaItems"] = audioMediaItems.map(\.jsonObject)
        }
        if let ownerMediaTimeline, !ownerMediaTimeline.isEmpty {
            payload["ownerMediaTimeline"] = ownerMediaTimeline.map(\.jsonObject)
        }

        let observationContexts = observationContextObjects(from: observationContextsJSON)
        if !observationContexts.isEmpty {
            payload["observation_contexts"] = observationContexts
        }
        payload["mimeType"] = mimeType
        if let preferredGoal {
            payload["preferred_goal"] = [
                "user_field_trip_id": preferredGoal.userFieldTripId,
                "item_id": preferredGoal.itemId
            ]
        }

        return try jsonData(from: payload)
    }

    static func normalizedGeoprivacy(_ value: String) -> String {
        switch value {
        case "private", "obscured":
            return value
        default:
            return "open"
        }
    }

    private static func telemetryPayloadFields(
        telemetry: CaptureTelemetry,
        context: InferencePayloadContext,
        clientScanId: String?
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "user_id": context.userId,
            "deviceLocale": context.deviceLocale,
            "deviceTimeZone": context.deviceTimeZone,
            "currentMonth": context.currentMonth,
            "timeOfDay": context.timeOfDay
        ]

        setIfPresent(context.depthScaleText, forKey: "depthScaleText", in: &payload)
        setIfPresent(telemetry.zoomFactor.map { Double($0) }, forKey: "zoomFactor", in: &payload)
        setIfPresent(telemetry.gpsLatitude, forKey: "gpsLatitude", in: &payload)
        setIfPresent(telemetry.gpsLongitude, forKey: "gpsLongitude", in: &payload)
        setIfPresent(telemetry.gpsElevation, forKey: "gpsElevation", in: &payload)
        let publicLocationLabel = context.defaultGeoprivacy == "private"
            ? nil
            : ExploreLocationPrivacy.displayLabel(from: telemetry.locationName)
        setIfPresent(telemetry.locationName, forKey: "semanticLocation", in: &payload)
        setIfPresent(publicLocationLabel, forKey: "publicLocationLabel", in: &payload)
        setIfPresent(context.defaultGeoprivacy, forKey: "geoprivacy", in: &payload)
        setIfPresent(telemetry.weatherCondition, forKey: "weatherCondition", in: &payload)
        setIfPresent(telemetry.weatherTemperatureF, forKey: "weatherTemperatureF", in: &payload)
        setIfPresent(context.deviceRegion, forKey: "deviceRegion", in: &payload)
        setIfPresent(telemetry.timestamp, forKey: "timestamp", in: &payload)
        setIfPresent(telemetry.estimatedSizeCm, forKey: "estimated_size_cm", in: &payload)
        setIfPresent(clientScanId, forKey: "client_scan_id", in: &payload)

        return payload
    }

    private static func observationContextObject(from json: String?) -> [String: Any]? {
        json.flatMap { rawJSON in
            guard let data = rawJSON.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private static func observationContextObjects(from jsons: [String]) -> [[String: Any]] {
        jsons.compactMap { json in
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private static func setIfPresent<T>(
        _ value: T?,
        forKey key: String,
        in payload: inout [String: Any]
    ) {
        if let value {
            payload[key] = value
        }
    }

    private static func jsonData(from payload: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: payload)
    }
}
