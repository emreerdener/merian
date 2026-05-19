import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import Merian

final class ShareImportTests: XCTestCase {
    func testItemProviderImageSupport() {
        let imageProvider = NSItemProvider(item: Data([0xFF, 0xD8, 0xFF]) as NSData, typeIdentifier: UTType.jpeg.identifier)
        let textProvider = NSItemProvider(item: "hello" as NSString, typeIdentifier: UTType.plainText.identifier)

        XCTAssertTrue(ShareImportItemProviderResolver.supportsImage(imageProvider))
        XCTAssertFalse(ShareImportItemProviderResolver.supportsImage(textProvider))
    }

    func testImagePreparationExtractsExifDateAndGPS() throws {
        let url = try makeJPEGFixture()
        defer { try? FileManager.default.removeItem(at: url) }

        let prepared = try ShareImportImagePreparer.prepare(
            fileURL: url,
            scanId: "11111111-1111-4111-8111-111111111111"
        )

        XCTAssertFalse(prepared.imageData.isEmpty)
        XCTAssertEqual(prepared.stagingFileName, "11111111-1111-4111-8111-111111111111_share_import.\(prepared.fileExtension)")
        XCTAssertEqual(prepared.telemetry.gpsLatitude ?? 0, 30.25, accuracy: 0.0001)
        XCTAssertEqual(prepared.telemetry.gpsLongitude ?? 0, -97.75, accuracy: 0.0001)
        XCTAssertNotNil(prepared.telemetry.timestamp)
    }

    func testReceiptStoreRoundTripAndRemoval() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let receipt = ShareImportReceipt(
            scanId: "11111111-1111-4111-8111-111111111111",
            createdAt: Date(timeIntervalSince1970: 1_777_000_000),
            status: .queued
        )
        try ShareImportReceiptStore.write(
            ShareImportReceiptSnapshot(receipts: [receipt]),
            rootURL: rootURL
        )

        XCTAssertEqual(ShareImportReceiptStore.load(rootURL: rootURL).receipts, [receipt])

        ShareImportReceiptStore.remove(scanIds: [receipt.scanId], rootURL: rootURL)
        XCTAssertTrue(ShareImportReceiptStore.load(rootURL: rootURL).receipts.isEmpty)
    }

    func testMissingSharedSettingsDoNotBlockShareImport() {
        XCTAssertFalse(ShareImportSettingsSnapshot.fallback.blocksShareImport)

        let exhaustedSnapshot = ShareImportSettingsSnapshot(
            generatedAt: Date(),
            requiresScanConfirmation: false,
            isProActive: false,
            freeScansRemaining: 0,
            alphaUnlimitedFreeScansEnabled: false
        )
        XCTAssertTrue(exhaustedSnapshot.blocksShareImport)
    }

    func testAuthSessionParsingAndMigrationSelection() throws {
        let sessionData = try JSONSerialization.data(withJSONObject: [
            "accessToken": "header.\(Self.jwtPayload(exp: Date().addingTimeInterval(3_600))).sig",
            "refreshToken": "refresh-token",
            "expiresAt": Date().addingTimeInterval(3_600).timeIntervalSince1970,
            "user": ["id": "22222222-2222-4222-8222-222222222222"]
        ])

        let session = ShareImportAuthStore.parseSessionData(sessionData)
        XCTAssertEqual(session?.refreshToken, "refresh-token")
        XCTAssertEqual(session?.userId, "22222222-2222-4222-8222-222222222222")
        XCTAssertEqual(
            ShareImportAuthStore.migratedSessionData(legacyData: sessionData, sharedData: nil),
            sessionData
        )
        XCTAssertNil(
            ShareImportAuthStore.migratedSessionData(legacyData: nil, sharedData: sessionData)
        )
    }

    private func makeJPEGFixture() throws -> URL {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12))
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jpg")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil),
              let cgImage = image.cgImage else {
            throw CocoaError(.fileWriteUnknown)
        }

        let properties: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifDateTimeOriginal: "2026:05:18 12:30:00"
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 30.25,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 97.75,
                kCGImagePropertyGPSLongitudeRef: "W",
                kCGImagePropertyGPSAltitude: 150
            ]
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    private static func jwtPayload(exp: Date) -> String {
        let payloadData = try! JSONSerialization.data(withJSONObject: ["exp": exp.timeIntervalSince1970])
        return payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
