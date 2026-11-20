import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Merian

@Suite("Native camera framing recipe", .serialized)
@MainActor
struct SharedMediaNativeCameraRecipeTests {
    @Test(arguments: [0.0, 0.25, 1.0], [1, 6, 11, 16])
    func verifiedOriginalProducesBothFramedOutputs(center: Double, configuration: Int) async throws {
        let landscape = configuration > 10, orientation = configuration % 10
        let h = try SharedMediaNativePreparationTests.Harness(), owner = try await h.open()
        try owner.setPreparationFault(nil, focusFactory: .qualification(.qualification(worker: { .noCandidates }, drainRegistered: {})))
        let bytes = try image(landscape: landscape, orientation: orientation)
        let request = try await owner.prepareOriginal(packageID: h.packageID, draftGeneration: h.draft, ordinal: 0, kind: .camera)
        let result = try await owner.acquireOriginal(request) { bytes }
        let reference = PhotoOriginalReference(ownerID: h.ownerID, packageID: h.packageID, referenceID: result.referenceID,
            assetID: result.assetID, assetGeneration: result.assetGeneration, draftGeneration: h.draft, referenceRevision: result.referenceRevision)
        let recipe = recipe(center)
        let output = try await owner.qualifyPhotoPreparation(original: reference, recipe: recipe)
        #expect(try Data(contentsOf: h.file(reference)) == bytes)
        for (actual, maximum) in [(output.ai, ImagePreparationPolicy.inferenceMaxDimension(isProActive: false)), (output.display, ImagePreparationPolicy.displayMaxDimension)] {
            let decoded = try #require(ImageDownsampler.downsample(data: bytes, maxSize: maximum))
            let width = Double(decoded.width), height = Double(decoded.height), side = Double(min(decoded.width, decoded.height))
            let expected = try #require(decoded.cropping(to: CGRect(x: (width - side) / 2,
                y: min(max(height * center - side / 2, 0), height - side), width: side, height: side)))
            #expect(actual == ImageCropProcessor.encode(expected))
        }
        #expect(output.intent.preparation.recipe == recipe)
        try await owner.abandonPreparation(output.attempt)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func oldRecipeAttemptIntentAndEnvelopesRetainCanonicalBytes() async throws {
        let oldRecipe = Data(#"{"format":"nativeStillImageV1","isPro":false,"offsetX":0,"offsetY":0,"quarterTurns":0,"scale":1}"#.utf8)
        let decoded = try JSONDecoder().decode(SharedMediaNativePreparationRecipe.self, from: oldRecipe)
        #expect(try SharedMediaNativeDraftEnvelope.bytes(decoded) == oldRecipe)
        let h = try SharedMediaNativePreparationTests.Harness(), owner = try await h.open(), original = try await h.acquire(owner)
        try owner.setPreparationFault(nil, focusFactory: .qualification(.qualification(worker: { .noCandidates }, drainRegistered: {})))
        let output = try await owner.qualifyPhotoPreparation(original: original, recipe: decoded)
        let attemptBytes = try output.attempt.encoded(), intentBytes = try output.intent.encoded()
        // Check containing wire-shaped values, not just an isolated recipe. Each
        // recipe must equal the pre-extension golden object, without a null key.
        let golden = try #require(JSONSerialization.jsonObject(with: oldRecipe) as? NSDictionary)
        let attemptObject = try #require(JSONSerialization.jsonObject(with: attemptBytes) as? NSDictionary)
        let intentObject = try #require(JSONSerialization.jsonObject(with: intentBytes) as? NSDictionary)
        #expect(attemptObject["recipe"] as? NSDictionary == golden)
        #expect((intentObject["preparation"] as? NSDictionary)?["recipe"] as? NSDictionary == golden)
        #expect(try SharedMediaNativePreparationAttempt.decode(attemptBytes).encoded() == attemptBytes)
        #expect(try SharedMediaNativeDerivativeIntent.decode(intentBytes).encoded() == intentBytes)
        let reserved = try h.state().envelope
        if case .preparation(let value) = try SharedMediaNativeDraftEnvelope.decode(reserved) { #expect(try value.encoded() == reserved) }
        else { Issue.record("Expected retained attempt envelope") }
        let completed = try SharedMediaNativeDraftEnvelope.V2(version: 2, contexts: [], presentation: [], sequence: 1,
            attempt: nil, intents: [.init(bytes: intentBytes)], frozen: nil).encoded()
        #expect(try SharedMediaNativeDraftEnvelope.V2.decode(completed).encoded() == completed)
        try await owner.abandonPreparation(output.attempt)
        #expect(await owner.invalidateAndAwaitForAccountTransition())
    }

    @Test func malformedOrMixedRecipesFailClosed() throws {
        for center in [-0.01, 1.01, Double.infinity, Double.nan] {
            #expect(throws: (any Error).self) { try recipe(center).validate() }
        }
        for bad in [
            SharedMediaNativePreparationRecipe(format: .cameraStill, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0),
            .init(format: .cameraStill, isPro: false, cropDisplaySize: 200, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: 0.5),
            .init(format: .cameraStill, isPro: false, cropDisplaySize: nil, quarterTurns: 1, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: 0.5),
            .init(format: .stillImage, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: 0.5)
        ] { #expect(throws: (any Error).self) { try bad.validate() } }
        let encoded = try SharedMediaNativeDraftEnvelope.bytes(recipe(0.25))
        let unknown = Data(String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "nativeCameraStillV1", with: "unknownCamera").utf8)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(SharedMediaNativePreparationRecipe.self, from: unknown) }
    }

    @Test(arguments: [0.0, 0.25, 0.75, 1.0], [false, true])
    func recropInitialOffsetPreservesClampedSourceWindow(center: Double, landscape: Bool) throws {
        let size = landscape ? CGSize(width: 300, height: 100) : CGSize(width: 100, height: 300)
        let side = min(size.width, size.height), display: CGFloat = 200
        let offset = try #require(ImageCropProcessor.initialSquareCropOffset(imageSize: size, displaySize: display, verticalCenterFraction: center))
        let recoveredY = (size.height - side) / 2 - offset.height / display * side
        #expect(abs(recoveredY - min(max(size.height * center - side / 2, 0), size.height - side)) < 0.001)
        #expect(offset.width == 0)
        #expect(ImageCropProcessor.initialSquareCropOffset(imageSize: .zero, displaySize: display, verticalCenterFraction: center) == nil)
    }

    private func recipe(_ center: Double) -> SharedMediaNativePreparationRecipe {
        .init(format: .cameraStill, isPro: false, cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: center)
    }
    private func image(landscape: Bool, orientation: Int) throws -> Data {
        let size = landscape ? CGSize(width: 300, height: 150) : CGSize(width: 150, height: 300)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    UIColor(red: CGFloat(x) / size.width, green: CGFloat(y) / size.height, blue: 0.3, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let bytes = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return bytes as Data
    }
}
