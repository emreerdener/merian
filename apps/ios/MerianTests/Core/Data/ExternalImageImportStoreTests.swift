import CoreGraphics
import CoreLocation
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Merian

@Suite("External image import store")
struct ExternalImageImportStoreTests {
    private final class SecurityScopeRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var active = false
        private var recordedEvents: [String] = []

        func start() {
            lock.lock()
            active = true
            recordedEvents.append("start")
            lock.unlock()
        }

        func validate() -> Bool {
            lock.lock()
            recordedEvents.append("validate")
            let isActive = active
            lock.unlock()
            return isActive
        }

        func stop() {
            lock.lock()
            recordedEvents.append("stop")
            active = false
            lock.unlock()
        }

        var events: [String] {
            lock.lock()
            let events = recordedEvents
            lock.unlock()
            return events
        }
    }

    @Test func routesIncomingURLsWithoutChangingExistingHandlerPrecedence() {
        let fileURL = URL(fileURLWithPath: "/tmp/shared-photo.jpg")
        let deepLink = URL(string: "naturebook://scan/example")!
        let universalLink = URL(string: "https://naturebook.earth/explore/post/example")!
        let legacyDeepLink = URL(string: "merian://scan/example")!
        let legacyUniversalLink = URL(string: "https://merian.earth/explore/post/example")!
        let authURL = URL(string: "https://example.supabase.co/auth/v1/callback?code=abc")!

        #expect(MerianOpenURLRoute.classify(authURL, googleHandled: true) == .handledByGoogle)
        #expect(MerianOpenURLRoute.classify(deepLink, googleHandled: false) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(universalLink, googleHandled: false) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(legacyDeepLink, googleHandled: false) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(legacyUniversalLink, googleHandled: false) == .merianDeepLink)
        #expect(MerianOpenURLRoute.classify(fileURL, googleHandled: false) == .externalImageImport)
        #expect(MerianOpenURLRoute.classify(authURL, googleHandled: false) == .supabaseAuthentication)
    }

    @Test func classifiesOnlyFileBackedImages() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let imageURL = root.appendingPathComponent("shared-photo.jpg")
        let textURL = root.appendingPathComponent("notes.txt")
        try Data([0xFF, 0xD8, 0xFF]).write(to: imageURL)
        try Data("not an image".utf8).write(to: textURL)

        #expect(ExternalImageImportURLClassifier.isSupportedImageFileURL(imageURL))
        #expect(!ExternalImageImportURLClassifier.isSupportedImageFileURL(textURL))
        #expect(!ExternalImageImportURLClassifier.isSupportedImageFileURL(
            URL(string: "naturebook://scan/example")!
        ))
        #expect(!ExternalImageImportURLClassifier.isSupportedImageFileURL(
            URL(string: "https://naturebook.earth/explore/post/example")!
        ))
    }

    @Test func persistsPendingImportAcrossStoreInstancesAndCleansUpAfterAcknowledgement() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("source.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
        let inboxURL = root.appendingPathComponent("Inbox", isDirectory: true)

        let firstStore = ExternalImageImportStore(rootURL: inboxURL)
        let staged = try await firstStore.stageIncomingImage(at: sourceURL)
        let storedURL = try #require(await firstStore.fileURL(for: staged))
        #expect(FileManager.default.fileExists(atPath: storedURL.path))

        let relaunchedStore = ExternalImageImportStore(rootURL: inboxURL)
        let relaunchedPendingImports = await relaunchedStore.pendingImports()
        #expect(relaunchedPendingImports == [staged])

        await relaunchedStore.remove(staged)
        #expect((await relaunchedStore.pendingImports()).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storedURL.path))
    }

    @Test func acquiresSecurityScopeBeforeValidationAndReleasesItAfterCopy() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("source.jpg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: sourceURL)
        let recorder = SecurityScopeRecorder()
        let securityScope = ExternalImageImportSecurityScope(
            startAccessing: { _ in
                recorder.start()
                return true
            },
            stopAccessing: { _ in recorder.stop() }
        )
        let store = ExternalImageImportStore(
            rootURL: root.appendingPathComponent("Inbox"),
            securityScope: securityScope,
            fileTypeValidator: { _ in recorder.validate() }
        )

        _ = try await store.stageIncomingImage(at: sourceURL)

        #expect(recorder.events == ["start", "validate", "stop"])
    }

    @Test func recoversCommittedOrphanAndRemovesInterruptedTemporaryCopy() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inboxURL = root.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)
        let orphanId = UUID()
        let orphanURL = inboxURL.appendingPathComponent("\(orphanId.uuidString).jpg")
        let interruptedURL = inboxURL.appendingPathComponent(".incoming-\(UUID().uuidString)")
        try Data([0xFF, 0xD8, 0xFF]).write(to: orphanURL)
        try Data([0xFF]).write(to: interruptedURL)

        let pendingImports = await ExternalImageImportStore(rootURL: inboxURL).pendingImports()

        #expect(pendingImports.map(\.id) == [orphanId])
        #expect(!FileManager.default.fileExists(atPath: interruptedURL.path))
    }

    @Test func persistsTerminalFailureUntilCaptureWorkspaceAcknowledgesIt() async {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let inboxURL = root.appendingPathComponent("Inbox", isDirectory: true)

        await ExternalImageImportStore(rootURL: inboxURL).recordTerminalFailure()
        let relaunchedStore = ExternalImageImportStore(rootURL: inboxURL)

        #expect(await relaunchedStore.consumeTerminalFailure())
        #expect(!(await relaunchedStore.consumeTerminalFailure()))
    }

    @Test func prunesManifestEntriesWhoseFilesAreMissing() async throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceURL = root.appendingPathComponent("source.heic")
        try Data([0x00, 0x00, 0x00, 0x18]).write(to: sourceURL)
        let store = ExternalImageImportStore(rootURL: root.appendingPathComponent("Inbox"))
        let staged = try await store.stageIncomingImage(at: sourceURL)
        let storedURL = try #require(await store.fileURL(for: staged))
        try FileManager.default.removeItem(at: storedURL)

        #expect((await store.pendingImports()).isEmpty)
    }

    @Test func extractsSignedGpsAndOffsetCaptureDate() throws {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:15 17:05:04",
                "OffsetTimeOriginal": "-05:00"
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 41.8781,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 87.6298,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        ]

        let metadata = ImportedImageMetadataExtractor.metadata(
            fromProperties: properties,
            defaultTimeZone: try #require(TimeZone(secondsFromGMT: 0))
        )

        #expect(metadata.latitude == 41.8781)
        #expect(metadata.longitude == -87.6298)
        #expect(metadata.captureDate == makeDate("2026-07-15T22:05:04Z"))
    }

    @Test func preservesDateOnlyMetadataWithoutInventingLocation() throws {
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:15 17:05:04"
            ]
        ]

        let metadata = ImportedImageMetadataExtractor.metadata(
            fromProperties: properties,
            defaultTimeZone: try #require(TimeZone(secondsFromGMT: 0))
        )

        #expect(metadata.captureDate == makeDate("2026-07-15T17:05:04Z"))
        #expect(metadata.latitude == nil)
        #expect(metadata.longitude == nil)
    }

    @Test func preservesCompleteCoordinateOnlyAndRejectsPartialOrInvalidCoordinates() {
        let coordinateOnly: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.45,
                kCGImagePropertyGPSLatitudeRef: "S",
                kCGImagePropertyGPSLongitude: 18.42,
                kCGImagePropertyGPSLongitudeRef: "E"
            ]
        ]
        let partialCoordinate: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.45,
                kCGImagePropertyGPSLatitudeRef: "S"
            ]
        ]
        let invalidCoordinate: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 91,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 18.42,
                kCGImagePropertyGPSLongitudeRef: "E"
            ]
        ]
        let missingHemisphere: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 33.45,
                kCGImagePropertyGPSLongitude: 18.42,
                kCGImagePropertyGPSLongitudeRef: "E"
            ]
        ]

        let coordinateMetadata = ImportedImageMetadataExtractor.metadata(fromProperties: coordinateOnly)
        let partialMetadata = ImportedImageMetadataExtractor.metadata(fromProperties: partialCoordinate)
        let invalidMetadata = ImportedImageMetadataExtractor.metadata(fromProperties: invalidCoordinate)
        let missingHemisphereMetadata = ImportedImageMetadataExtractor.metadata(
            fromProperties: missingHemisphere
        )

        #expect(coordinateMetadata.latitude == -33.45)
        #expect(coordinateMetadata.longitude == 18.42)
        #expect(partialMetadata.latitude == nil)
        #expect(partialMetadata.longitude == nil)
        #expect(invalidMetadata.latitude == nil)
        #expect(invalidMetadata.longitude == nil)
        #expect(missingHemisphereMetadata.latitude == nil)
        #expect(missingHemisphereMetadata.longitude == nil)
    }

    @Test func malformedImageProducesEmptyMetadata() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let malformedURL = root.appendingPathComponent("malformed.jpg")
        try Data("not image bytes".utf8).write(to: malformedURL)

        let metadata = ImportedImageMetadataExtractor.extract(from: malformedURL)

        #expect(metadata.captureDate == nil)
        #expect(metadata.latitude == nil)
        #expect(metadata.longitude == nil)
    }

    @Test func extractsMetadataThroughImageIOFromRealJpegFixture() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureURL = root.appendingPathComponent("metadata-fixture.jpg")
        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:07:15 17:05:04",
                "OffsetTimeOriginal": "-05:00"
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 41.8781,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 87.6298,
                kCGImagePropertyGPSLongitudeRef: "W"
            ]
        ]
        try makeJPEGData(properties: properties).write(to: fixtureURL)

        let metadata = ImportedImageMetadataExtractor.extract(from: fixtureURL)

        #expect(metadata.captureDate == makeDate("2026-07-15T22:05:04Z"))
        #expect(metadata.latitude == 41.8781)
        #expect(metadata.longitude == -87.6298)
    }

    @Test func realJpegWithoutMetadataDoesNotInventContext() throws {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fixtureURL = root.appendingPathComponent("no-metadata.jpg")
        try makeJPEGData(properties: [:]).write(to: fixtureURL)

        let metadata = ImportedImageMetadataExtractor.extract(from: fixtureURL)

        #expect(metadata.captureDate == nil)
        #expect(metadata.latitude == nil)
        #expect(metadata.longitude == nil)
    }

    @Test func galleryTelemetryNeverFallsBackToCurrentDeviceContext() async {
        let currentDeviceLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 30,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: Date()
        )

        let immediate = CaptureTelemetry.immediateForActiveScan(
            historicalContext: nil,
            isGalleryPhoto: true,
            cachedLocation: currentDeviceLocation,
            distanceMeters: 1,
            zoomFactor: 2
        )
        let resolved = await CaptureTelemetry.resolveForActiveScan(
            resolvedContext: EnvironmentContext(
                location: currentDeviceLocation,
                locationName: "Current device location",
                weatherCondition: "Clear",
                weatherTemperature: 75,
                captureDate: Date()
            ),
            historicalContext: nil,
            isGalleryPhoto: true,
            firstImageData: nil,
            distanceMeters: 1,
            zoomFactor: 2
        )

        #expect(immediate.gpsLatitude == nil)
        #expect(immediate.gpsLongitude == nil)
        #expect(immediate.timestamp == nil)
        #expect(resolved.gpsLatitude == nil)
        #expect(resolved.gpsLongitude == nil)
        #expect(resolved.timestamp == nil)
    }

    @Test func coordinateOnlyHistoricalTelemetryPreservesCoordinatesWithoutDate() {
        let coordinateOnlyContext = EnvironmentContext(
            location: CLLocation(latitude: 33.45, longitude: 18.42),
            locationName: nil,
            weatherCondition: nil,
            weatherTemperature: nil,
            captureDate: nil
        )

        let telemetry = CaptureTelemetry(
            from: coordinateOnlyContext,
            distance: nil,
            requiresExplicitCaptureDate: true
        )

        #expect(telemetry.gpsLatitude == 33.45)
        #expect(telemetry.gpsLongitude == 18.42)
        #expect(telemetry.timestamp == nil)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("external-image-import-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private func makeJPEGData(properties: [CFString: Any]) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 8,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw CocoaError(.coderInvalidValue)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data as Data
    }
}
