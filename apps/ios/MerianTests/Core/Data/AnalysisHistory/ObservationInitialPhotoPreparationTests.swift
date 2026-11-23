import Foundation
@testable import Merian
import Testing

struct ObservationInitialPhotoPreparationTests {
    func recipe() -> SharedMediaNativePreparationRecipe {
        .init(format: .selectedStillImage, isPro: true, cropDisplaySize: 390,
              quarterTurns: 1, scale: 1.5, offsetX: -30, offsetY: 25,
              sourceSelection: .init(x: 0.2, y: 0.3, width: 0.1, height: 0.2, source: .userSelection))
    }

    @Test func projectsOnlyValidatedGeometryAndNormalizesZeroFingerprint() throws {
        let geometry = try ObservationInitialPhotoPreparation(recipe: recipe())
        #expect(try ObservationInitialPhotoPreparation(geometry.object) == geometry)
        #expect(geometry.object["isPro"] == nil)
        #expect(geometry.object["environment"] == nil)
        var positive = geometry.object, negative = geometry.object
        positive["offset_x"] = 0.0; negative["offset_x"] = -0.0
        #expect(try ObservationInitialPhotoPreparation(positive).fingerprintFields == ObservationInitialPhotoPreparation(negative).fingerprintFields)
        let deltas: [[String: Any]] = [["isPro": true], ["offset_x": true], ["quarter_turns": 1.5], ["scale": 0.5],
                                    ["source_selection": NSNull()], ["crop_display_size": NSNull()], ["camera_vertical_center": 0.5]]
        for delta in deltas {
            let value = geometry.object.merging(delta) { _, new in new }
            #expect(throws: (any Error).self) { try ObservationInitialPhotoPreparation(value) }
        }
    }

    @Test func preservesFullAspectAndCameraSemantics() throws {
        let full = try ObservationInitialPhotoPreparation(recipe: .init(format: .stillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0))
        #expect(full.isFullFrame)
        let camera = try ObservationInitialPhotoPreparation(recipe: .init(format: .cameraStill, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0, cameraVerticalCenter: 0.7))
        #expect(!camera.isFullFrame)
        #expect(camera.cameraVerticalCenter == 0.7)
        #expect(try ObservationInitialPhotoPreparation(camera.object) == camera)
    }

    @Test func fullAspectSelectionRequiresIdentityGeometry() throws {
        let selected = try ObservationInitialPhotoPreparation(recipe: .init(format: .selectedStillImage, isPro: false,
            cropDisplaySize: nil, quarterTurns: 0, scale: 1, offsetX: 0, offsetY: 0,
            sourceSelection: recipe().sourceSelection))
        #expect(selected.isFullFrame)
        #expect(try ObservationInitialPhotoPreparation(selected.object) == selected)
        for delta: [String: Any] in [["quarter_turns": 1], ["scale": 1.1], ["offset_x": 1], ["offset_y": 1],
                                    ["camera_vertical_center": 0.5], ["source_selection": NSNull()]] {
            #expect(throws: (any Error).self) {
                try ObservationInitialPhotoPreparation(selected.object.merging(delta) { _, new in new })
            }
        }
    }
}
