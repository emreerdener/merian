import Foundation
import Testing

@testable import Merian

@Suite("Inference Payload Builder")
struct InferencePayloadBuilderTests {
    @Test func multimodalRequestBodyUsesActiveCamelCaseTelemetryContract() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: 1.3,
            gpsLatitude: 37.7749,
            gpsLongitude: -122.4194,
            gpsElevation: 42.5,
            locationName: "Zilker Park",
            weatherCondition: "Partly Cloudy",
            weatherTemperatureF: 68.0,
            timeOfDay: nil,
            timestamp: "2026-04-24T10:30:00.000Z",
            zoomFactor: 2.0,
            estimatedSizeCm: 11.5
        )
        let observationContextJSON = """
        {"freeText":"Heard rustling before spotting it","addedAt":"2026-04-24T10:29:30.000Z"}
        """

        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: ["staging/test-user/image.webp"],
            base64ImageDatas: ["ZmFrZV9pbWFnZQ=="],
            audioBase64s: ["ZmFrZV9hdWRpbw=="],
            observationContextsJSON: [observationContextJSON],
            userId: "test-user",
            mimeType: "image/webp",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: "1.3 meters",
            clientScanId: "scan-123",
            preferredGoal: FieldTripPreferredGoal(
                userFieldTripId: "00000000-0000-4000-8000-000000000001",
                itemId: "00000000-0000-4000-8000-000000000002"
            )
        )

        let payload = try jsonPayload(bodyData)
        #expect(payload["gpsLatitude"] as? Double == 37.7749)
        #expect(payload["gpsLongitude"] as? Double == -122.4194)
        #expect(payload["gpsElevation"] as? Double == 42.5)
        #expect(payload["semanticLocation"] as? String == "Zilker Park")
        #expect(payload["publicLocationLabel"] == nil)
        #expect(payload["weatherCondition"] as? String == "Partly Cloudy")
        #expect(payload["deviceLocale"] as? String == "en")
        #expect(payload["deviceTimeZone"] as? String == "America/Chicago")
        #expect(payload["deviceRegion"] as? String == "US")
        #expect(payload["currentMonth"] as? Int == 4)
        #expect(payload["timeOfDay"] as? String == "10:30 AM")
        #expect(payload["depthScaleText"] as? String == "1.3 meters")
        #expect(payload["zoomFactor"] as? Double == 2.0)
        #expect(payload["estimated_size_cm"] as? Double == 11.5)
        #expect(payload["client_scan_id"] as? String == "scan-123")
        let preferredGoal = try #require(payload["preferred_goal"] as? [String: String])
        #expect(preferredGoal["user_field_trip_id"] == "00000000-0000-4000-8000-000000000001")
        #expect(preferredGoal["item_id"] == "00000000-0000-4000-8000-000000000002")
        #expect(payload["gps_latitude"] == nil)
        #expect(payload["semantic_location"] == nil)

        let contexts = try #require(payload["observation_contexts"] as? [[String: Any]])
        #expect(contexts.count == 1)
        #expect(contexts[0]["freeText"] as? String == "Heard rustling before spotting it")
        #expect(contexts[0]["addedAt"] as? String == "2026-04-24T10:29:30.000Z")
        #expect(contexts[0]["free_text"] == nil)
    }

    @Test func multimodalRequestBodyIncludesPublicLocationLabelWhenDerivable() throws {
        let telemetry = CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: "123 Main St, Austin, TX, United States",
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: nil,
            zoomFactor: nil,
            estimatedSizeCm: nil
        )

        let payload = try jsonPayload(makeBody(telemetry: telemetry))
        #expect(payload["semanticLocation"] as? String == "123 Main St, Austin, TX, United States")
        #expect(payload["publicLocationLabel"] as? String == "Austin, TX")
        #expect(payload["public_location_label"] == nil)
    }

    @Test func multimodalRequestBodyCarriesStagedAudioR2KeysWithoutInlineAudio() throws {
        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: ["staging/test-user/image.webp"],
            audioR2ObjectKeys: ["staging/test-user/audio.wav"],
            userId: "test-user",
            telemetry: emptyTelemetry(timestamp: "2026-04-24T10:30:00.000Z"),
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-audio-r2"
        )

        let payload = try jsonPayload(bodyData)
        #expect(payload["r2ObjectKeys"] as? [String] == ["staging/test-user/image.webp"])
        #expect(payload["audioR2ObjectKeys"] as? [String] == ["staging/test-user/audio.wav"])
        #expect(payload["audioBase64s"] == nil)
        #expect(payload["client_scan_id"] as? String == "scan-audio-r2")
    }

    @Test func multimodalRequestBodyCarriesCanonicalAudioDescriptionTimeline() throws {
        let contextJSON = """
        {"freeText":"Low rhythmic sound in a quiet room","addedAt":808981800}
        """
        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            audioBase64s: ["ZmFrZV9hdWRpbw=="],
            audioMediaItems: [.audio(sourceIndex: 0)],
            ownerMediaTimeline: [
                .audio(audioInputIndex: 0, sourceIndex: 0),
                .description(contextIndex: 0)
            ],
            observationContextsJSON: [contextJSON],
            userId: "test-user",
            telemetry: emptyTelemetry(timestamp: "2026-08-15T05:30:00.000Z"),
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 8,
            timeOfDay: "12:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-audio-description"
        )

        let payload = try jsonPayload(bodyData)
        let audioItems = try #require(payload["audioMediaItems"] as? [[String: Any]])
        #expect(audioItems.count == 1)
        #expect(audioItems[0]["kind"] as? String == "audio")
        #expect(audioItems[0]["sourceIndex"] as? Int == 0)
        let timeline = try #require(payload["ownerMediaTimeline"] as? [[String: Any]])
        #expect(timeline.count == 2)
        #expect(timeline[0]["kind"] as? String == "audio")
        #expect(timeline[0]["audioInputIndex"] as? Int == 0)
        #expect(timeline[0]["sourceIndex"] as? Int == 0)
        #expect(timeline[1]["kind"] as? String == "description")
        #expect(timeline[1]["contextIndex"] as? Int == 0)
    }

    @Test func multimodalRequestBodyCarriesVideoKeysAndOrderedFrameCount() throws {
        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: [
                "staging/test-user/video-frame-1.webp",
                "staging/test-user/video-frame-2.webp",
                "staging/test-user/video-frame-3.webp"
            ],
            videoR2ObjectKeys: ["staging/test-user/clip.mp4"],
            videoFrameCount: 3,
            userId: "test-user",
            telemetry: emptyTelemetry(timestamp: "2026-04-24T10:30:00.000Z"),
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-video-r2"
        )

        let payload = try jsonPayload(bodyData)
        #expect(payload["r2ObjectKeys"] as? [String] == [
            "staging/test-user/video-frame-1.webp",
            "staging/test-user/video-frame-2.webp",
            "staging/test-user/video-frame-3.webp"
        ])
        #expect(payload["videoR2ObjectKeys"] as? [String] == ["staging/test-user/clip.mp4"])
        #expect(payload["videoFrameCount"] as? Int == 3)
        #expect(payload["client_scan_id"] as? String == "scan-video-r2")
    }

    @Test func multimodalRequestBodyCarriesVideoAudioMetadata() throws {
        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: [
                "staging/test-user/video-frame-1.webp",
                "staging/test-user/video-frame-2.webp"
            ],
            audioR2ObjectKeys: ["staging/test-user/video-audio.wav"],
            videoR2ObjectKeys: ["staging/test-user/clip.mp4"],
            videoFrameCount: 2,
            visualMediaItems: [
                .videoFrame(clipIndex: 0, frameIndex: 0),
                .videoFrame(clipIndex: 0, frameIndex: 1)
            ],
            audioMediaItems: [.videoAudio(clipIndex: 0)],
            userId: "test-user",
            telemetry: emptyTelemetry(timestamp: "2026-04-24T10:30:00.000Z"),
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-video-audio"
        )

        let payload = try jsonPayload(bodyData)
        let visualMediaItems = try #require(payload["visualMediaItems"] as? [[String: Any]])
        let audioMediaItems = try #require(payload["audioMediaItems"] as? [[String: Any]])
        #expect(visualMediaItems.count == 2)
        #expect(visualMediaItems[0]["kind"] as? String == "video_frame")
        #expect(visualMediaItems[0]["clipIndex"] as? Int == 0)
        #expect(audioMediaItems.count == 1)
        #expect(audioMediaItems[0]["kind"] as? String == "video_audio")
        #expect(audioMediaItems[0]["clipIndex"] as? Int == 0)
        #expect(payload["audioR2ObjectKeys"] as? [String] == ["staging/test-user/video-audio.wav"])
    }

    @Test func multimodalRequestBodyCarriesStillImageFocusWithoutAdditionalMedia() throws {
        let focusRegion = NormalizedImageFocusRegion(
            x: 0.1,
            y: 0.2,
            width: 0.5,
            height: 0.4
        )
        let bodyData = try MerianNetworkClient.buildMultiModalRequestBody(
            base64ImageDatas: ["encoded-image"],
            visualMediaItems: [.image(sourceIndex: 0, focusRegion: focusRegion)],
            userId: "test-user",
            telemetry: emptyTelemetry(timestamp: "2026-07-15T06:00:00.000Z"),
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 7,
            timeOfDay: "1:00 AM",
            depthScaleText: nil,
            clientScanId: "scan-focus"
        )

        let payload = try jsonPayload(bodyData)
        let visualItems = try #require(payload["visualMediaItems"] as? [[String: Any]])
        let encodedFocus = try #require(visualItems.first?["focusRegion"] as? [String: Any])
        #expect(payload["imageBase64s"] as? [String] == ["encoded-image"])
        #expect(visualItems.count == 1)
        #expect(encodedFocus["source"] as? String == "vision_objectness")
        #expect(encodedFocus["x"] as? Double == 0.1)
        #expect(encodedFocus["width"] as? Double == 0.5)
    }

    private func makeBody(telemetry: CaptureTelemetry) throws -> Data {
        try MerianNetworkClient.buildMultiModalRequestBody(
            r2ObjectKeys: ["staging/test-user/image.webp"],
            userId: "test-user",
            telemetry: telemetry,
            deviceLocale: "en",
            deviceTimeZone: "America/Chicago",
            deviceRegion: "US",
            currentMonth: 4,
            timeOfDay: "10:30 AM",
            depthScaleText: nil,
            clientScanId: "scan-123"
        )
    }

    private func emptyTelemetry(timestamp: String?) -> CaptureTelemetry {
        CaptureTelemetry(
            subjectDistanceInMeters: nil,
            gpsLatitude: nil,
            gpsLongitude: nil,
            gpsElevation: nil,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil,
            timeOfDay: nil,
            timestamp: timestamp,
            zoomFactor: nil,
            estimatedSizeCm: nil
        )
    }

    private func jsonPayload(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
