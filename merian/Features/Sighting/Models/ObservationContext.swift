import Foundation

// MARK: - ObservationContext

/// Structured description of a biological subject the user observed without capturing an image.
///
/// Used as the primary data payload for the Sighting submission path and reserved as an
/// optional enrichment parameter on the image scan path — allowing users to attach
/// descriptive context alongside a photo in a future release.
///
/// All enums conform to `Codable` and `CaseIterable` so they can be serialized into the
/// offline queue and iterated for UI chip generation without maintaining parallel arrays.
struct ObservationContext: Codable, Equatable, Sendable {

    var organismClass: OrganismClass?
    var colors: Set<ObservationColor> = []
    var size: ObservationSize?
    var habitat: Set<ObservationHabitat> = []
    var behaviors: Set<ObservationBehavior> = []
    var markings: Set<ObservationMarking> = []
    var texture: ObservationTexture?
    var freeText: String = ""

    /// True when the user has not selected any identifying descriptors.
    /// Organism class is the minimum required signal before submission is enabled.
    var isEmpty: Bool {
        organismClass == nil
            && colors.isEmpty
            && size == nil
            && habitat.isEmpty
            && behaviors.isEmpty
            && markings.isEmpty
            && texture == nil
            && freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Serializes the context into a structured plain-text block for the Gemini prompt.
    /// Key: value lines are always in a consistent order so the AI receives a stable format.
    func serialized() -> String {
        var lines: [String] = []
        if let o = organismClass {
            lines.append("Organism: \(o.displayName)")
        }
        if !colors.isEmpty {
            lines.append("Colors: \(colors.map(\.displayName).sorted().joined(separator: ", "))")
        }
        if let s = size {
            lines.append("Size: \(s.displayName)")
        }
        if !habitat.isEmpty {
            lines.append("Where: \(habitat.map(\.displayName).sorted().joined(separator: ", "))")
        }
        if !behaviors.isEmpty {
            lines.append("Behavior: \(behaviors.map(\.displayName).sorted().joined(separator: ", "))")
        }
        if !markings.isEmpty {
            lines.append("Markings: \(markings.map(\.displayName).sorted().joined(separator: ", "))")
        }
        if let t = texture {
            lines.append("Texture: \(t.displayName)")
        }
        let trimmed = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append("Notes: \(trimmed)")
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Organism Class

enum OrganismClass: String, CaseIterable, Codable, Sendable {
    case insect, bird, plant, mammal, reptile, fish, fungi, spider, other

    var displayName: String {
        switch self {
        case .insect:  return "Insect"
        case .bird:    return "Bird"
        case .plant:   return "Plant"
        case .mammal:  return "Mammal"
        case .reptile: return "Reptile"
        case .fish:    return "Fish"
        case .fungi:   return "Fungi"
        case .spider:  return "Spider"
        case .other:   return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .insect:  return "ant.fill"
        case .bird:    return "bird.fill"
        case .plant:   return "leaf.fill"
        case .mammal:  return "pawprint.fill"
        case .reptile: return "tortoise.fill"
        case .fish:    return "fish.fill"
        case .fungi:   return "allergens"
        case .spider:  return "ladybug.fill"
        case .other:   return "questionmark.circle.fill"
        }
    }
}

// MARK: - Color

struct ApproximateRGB {
    let r: Double
    let g: Double
    let b: Double
}

enum ObservationColor: String, CaseIterable, Codable, Sendable {
    case black, white, brown, gray, red, orange, yellow, green, blue, purple, metallic

    var displayName: String { rawValue.capitalized }

    /// Approximate swatch color for UI rendering.
    var approximateColor: ApproximateRGB {
        switch self {
        case .black:    return ApproximateRGB(r: 0.05, g: 0.05, b: 0.05)
        case .white:    return ApproximateRGB(r: 0.95, g: 0.95, b: 0.95)
        case .brown:    return ApproximateRGB(r: 0.55, g: 0.35, b: 0.15)
        case .gray:     return ApproximateRGB(r: 0.55, g: 0.55, b: 0.55)
        case .red:      return ApproximateRGB(r: 0.85, g: 0.15, b: 0.15)
        case .orange:   return ApproximateRGB(r: 0.95, g: 0.50, b: 0.10)
        case .yellow:   return ApproximateRGB(r: 0.95, g: 0.85, b: 0.10)
        case .green:    return ApproximateRGB(r: 0.20, g: 0.65, b: 0.25)
        case .blue:     return ApproximateRGB(r: 0.15, g: 0.40, b: 0.85)
        case .purple:   return ApproximateRGB(r: 0.55, g: 0.20, b: 0.75)
        case .metallic: return ApproximateRGB(r: 0.70, g: 0.70, b: 0.80)
        }
    }
}

// MARK: - Size

enum ObservationSize: String, CaseIterable, Codable, Sendable {
    case thumbnail, fingerLength, palmSized, forearmLength, larger

    var displayName: String {
        switch self {
        case .thumbnail:    return "Tiny (< 1 cm)"
        case .fingerLength: return "Small (1–5 cm)"
        case .palmSized:    return "Medium (5–15 cm)"
        case .forearmLength: return "Large (15–40 cm)"
        case .larger:       return "Very large (> 40 cm)"
        }
    }

    var shortLabel: String {
        switch self {
        case .thumbnail:    return "Tiny"
        case .fingerLength: return "Small"
        case .palmSized:    return "Medium"
        case .forearmLength: return "Large"
        case .larger:       return "Very large"
        }
    }
}

// MARK: - Habitat

enum ObservationHabitat: String, CaseIterable, Codable, Sendable {
    case onFlower, onBark, onGround, inWater, inAir, underRock, onLeaf, onWall

    var displayName: String {
        switch self {
        case .onFlower:  return "On a flower"
        case .onBark:    return "On tree bark"
        case .onGround:  return "On the ground"
        case .inWater:   return "In water"
        case .inAir:     return "In the air"
        case .underRock: return "Under a rock"
        case .onLeaf:    return "On a leaf"
        case .onWall:    return "On a wall"
        }
    }

    var systemImage: String {
        switch self {
        case .onFlower:  return "camera.macro"
        case .onBark:    return "tree.fill"
        case .onGround:  return "arrow.down.to.line"
        case .inWater:   return "drop.fill"
        case .inAir:     return "wind"
        case .underRock: return "oval.fill"
        case .onLeaf:    return "leaf.fill"
        case .onWall:    return "rectangle.fill"
        }
    }
}

// MARK: - Behavior

enum ObservationBehavior: String, CaseIterable, Codable, Sendable {
    case flying, crawling, walking, swimming, perching, stationary, burrowing

    var displayName: String {
        switch self {
        case .flying:     return "Flying"
        case .crawling:   return "Crawling"
        case .walking:    return "Walking"
        case .swimming:   return "Swimming"
        case .perching:   return "Perching"
        case .stationary: return "Stationary"
        case .burrowing:  return "Burrowing"
        }
    }

    var systemImage: String {
        switch self {
        case .flying:     return "paperplane.fill"
        case .crawling:   return "figure.walk"
        case .walking:    return "figure.walk"
        case .swimming:   return "figure.pool.swim"
        case .perching:   return "bird.fill"
        case .stationary: return "pause.fill"
        case .burrowing:  return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Marking

enum ObservationMarking: String, CaseIterable, Codable, Sendable {
    case spots, stripes, bands, solid, gradient, patchy

    var displayName: String {
        switch self {
        case .spots:    return "Spots"
        case .stripes:  return "Stripes"
        case .bands:    return "Bands"
        case .solid:    return "Solid color"
        case .gradient: return "Gradient"
        case .patchy:   return "Patchy"
        }
    }
}

// MARK: - Texture

enum ObservationTexture: String, CaseIterable, Codable, Sendable {
    case smooth, hairy, scaly, waxy, rough

    var displayName: String {
        switch self {
        case .smooth: return "Smooth"
        case .hairy:  return "Hairy / Fuzzy"
        case .scaly:  return "Scaly"
        case .waxy:   return "Waxy / Glossy"
        case .rough:  return "Rough"
        }
    }
}
