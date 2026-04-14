import Foundation
import Testing
@testable import Merian

@Suite("ObservationContext — model correctness")
struct ObservationContextTests {

    // MARK: - isEmpty

    @Test("Default context is empty")
    func testDefaultContextIsEmpty() {
        let context = ObservationContext()
        #expect(context.isEmpty)
    }

    @Test("Context with organism class is not empty")
    func testOrganismClassMakesContextNonEmpty() {
        var context = ObservationContext()
        context.organismClass = .insect
        #expect(!context.isEmpty)
    }

    @Test("Context with only freeText whitespace is still empty")
    func testWhitespaceOnlyFreeTextIsEmpty() {
        var context = ObservationContext()
        context.freeText = "   \n\t  "
        #expect(context.isEmpty)
    }

    @Test("Context with non-empty freeText is not empty")
    func testFreeTextContentMakesContextNonEmpty() {
        var context = ObservationContext()
        context.freeText = "Had spots on wings"
        #expect(!context.isEmpty)
    }

    @Test("Context with only colors is not empty")
    func testColorsAloneMakeContextNonEmpty() {
        var context = ObservationContext()
        context.colors = [.red, .black]
        #expect(!context.isEmpty)
    }

    @Test("Context with only size is not empty")
    func testSizeAloneMakesContextNonEmpty() {
        var context = ObservationContext()
        context.size = .palmSized
        #expect(!context.isEmpty)
    }

    @Test("Context with only habitat is not empty")
    func testHabitatAloneMakesContextNonEmpty() {
        var context = ObservationContext()
        context.habitat = [.onFlower]
        #expect(!context.isEmpty)
    }

    // MARK: - serialized()

    @Test("Empty context serializes to empty string")
    func testEmptyContextSerializesToEmptyString() {
        let context = ObservationContext()
        #expect(context.serialized().isEmpty)
    }

    @Test("Serialized output contains organism class line")
    func testSerializedContainsOrganismClass() {
        var context = ObservationContext()
        context.organismClass = .bird
        #expect(context.serialized().contains("Organism: Bird"))
    }

    @Test("Serialized output contains colors in sorted order")
    func testSerializedColorsAreSorted() {
        var context = ObservationContext()
        context.colors = [.green, .blue]
        let output = context.serialized()
        #expect(output.contains("Colors:"))
        // "Blue" sorts before "Green"
        let colorsLine = output.components(separatedBy: "\n").first(where: { $0.hasPrefix("Colors:") })
        #expect(colorsLine == "Colors: Blue, Green")
    }

    @Test("Serialized output contains size line")
    func testSerializedContainsSize() {
        var context = ObservationContext()
        context.size = .thumbnail
        #expect(context.serialized().contains("Size: Tiny (< 1 cm)"))
    }

    @Test("Serialized output contains habitat line")
    func testSerializedContainsHabitat() {
        var context = ObservationContext()
        context.habitat = [.inWater]
        #expect(context.serialized().contains("Where: In water"))
    }

    @Test("Serialized output contains behavior line")
    func testSerializedContainsBehavior() {
        var context = ObservationContext()
        context.behaviors = [.flying]
        #expect(context.serialized().contains("Behavior: Flying"))
    }

    @Test("Serialized output contains markings line")
    func testSerializedContainsMarkings() {
        var context = ObservationContext()
        context.markings = [.stripes]
        #expect(context.serialized().contains("Markings: Stripes"))
    }

    @Test("Serialized output contains texture line")
    func testSerializedContainsTexture() {
        var context = ObservationContext()
        context.texture = .hairy
        #expect(context.serialized().contains("Texture: Hairy / Fuzzy"))
    }

    @Test("Serialized output trims freeText whitespace")
    func testSerializedFreeTextIsTrimmed() {
        var context = ObservationContext()
        context.freeText = "  bright orange tips  "
        let output = context.serialized()
        #expect(output.contains("Notes: bright orange tips"))
        #expect(!output.contains("  bright"))
    }

    @Test("Full context serializes all fields in stable order")
    func testFullContextSerializationOrder() {
        var context = ObservationContext()
        context.organismClass = .insect
        context.colors = [.yellow]
        context.size = .fingerLength
        context.habitat = [.onFlower]
        context.behaviors = [.stationary]
        context.markings = [.spots]
        context.texture = .smooth
        context.freeText = "Yellow and black stripes"

        let lines = context.serialized().components(separatedBy: "\n")
        #expect(lines.count == 8)
        #expect(lines[0].hasPrefix("Organism:"))
        #expect(lines[1].hasPrefix("Colors:"))
        #expect(lines[2].hasPrefix("Size:"))
        #expect(lines[3].hasPrefix("Where:"))
        #expect(lines[4].hasPrefix("Behavior:"))
        #expect(lines[5].hasPrefix("Markings:"))
        #expect(lines[6].hasPrefix("Texture:"))
        #expect(lines[7].hasPrefix("Notes:"))
    }

    // MARK: - Codable round-trip

    @Test("ObservationContext encodes and decodes without loss")
    func testCodableRoundTrip() throws {
        var context = ObservationContext()
        context.organismClass = .spider
        context.colors = [.black, .gray]
        context.size = .palmSized
        context.habitat = [.underRock]
        context.behaviors = [.crawling]
        context.markings = [.bands]
        context.texture = .smooth
        context.freeText = "Eight legs, glossy body"

        let encoded = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(ObservationContext.self, from: encoded)

        #expect(decoded == context)
    }

    @Test("ObservationContext with empty sets round-trips cleanly")
    func testCodableRoundTripEmptySets() throws {
        let context = ObservationContext()
        let encoded = try JSONEncoder().encode(context)
        let decoded = try JSONDecoder().decode(ObservationContext.self, from: encoded)
        #expect(decoded == context)
        #expect(decoded.isEmpty)
    }

    // MARK: - Enum display names

    @Test("All OrganismClass cases have non-empty displayName and systemImage")
    func testOrganismClassMetadata() {
        for cls in OrganismClass.allCases {
            #expect(!cls.displayName.isEmpty, "displayName missing for \(cls)")
            #expect(!cls.systemImage.isEmpty,  "systemImage missing for \(cls)")
        }
    }

    @Test("All ObservationColor cases have valid swatch RGB values in 0–1 range")
    func testObservationColorSwatchRange() {
        for color in ObservationColor.allCases {
            let rgb = color.approximateColor
            #expect(rgb.r >= 0 && rgb.r <= 1, "Red channel out of range for \(color)")
            #expect(rgb.g >= 0 && rgb.g <= 1, "Green channel out of range for \(color)")
            #expect(rgb.b >= 0 && rgb.b <= 1, "Blue channel out of range for \(color)")
        }
    }

    @Test("All ObservationSize cases have non-empty displayName and shortLabel")
    func testObservationSizeLabels() {
        for size in ObservationSize.allCases {
            #expect(!size.displayName.isEmpty, "displayName missing for \(size)")
            #expect(!size.shortLabel.isEmpty,  "shortLabel missing for \(size)")
        }
    }

    @Test("All ObservationHabitat cases have non-empty displayName and systemImage")
    func testObservationHabitatMetadata() {
        for habitat in ObservationHabitat.allCases {
            #expect(!habitat.displayName.isEmpty, "displayName missing for \(habitat)")
            #expect(!habitat.systemImage.isEmpty,  "systemImage missing for \(habitat)")
        }
    }

    @Test("All ObservationBehavior cases have non-empty displayName and systemImage")
    func testObservationBehaviorMetadata() {
        for behavior in ObservationBehavior.allCases {
            #expect(!behavior.displayName.isEmpty, "displayName missing for \(behavior)")
            #expect(!behavior.systemImage.isEmpty,  "systemImage missing for \(behavior)")
        }
    }
}
