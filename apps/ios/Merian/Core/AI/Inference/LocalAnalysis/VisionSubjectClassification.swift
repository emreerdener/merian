import Foundation
import Vision

struct VisionClassificationCandidate: Sendable, Equatable {
    let identifier: String
    let confidence: Float
}

struct VisionSubjectClassification: Sendable, Equatable {
    let category: LocalSubjectCategory?
    let candidates: [VisionClassificationCandidate]
}

protocol VisionSubjectClassifying: Sendable {
    func classify(
        image: ImageDownsampler.SendableImage
    ) async throws -> VisionSubjectClassification
}

struct AppleVisionSubjectClassifier: VisionSubjectClassifying {
    func classify(
        image: ImageDownsampler.SendableImage
    ) async throws -> VisionSubjectClassification {
        let classificationTask = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(
                cgImage: image.cgImage,
                options: [:]
            )
            try autoreleasepool {
                try handler.perform([request])
            }
            try Task.checkCancellation()

            let candidates = (request.results ?? []).prefix(5).map {
                VisionClassificationCandidate(
                    identifier: $0.identifier,
                    confidence: $0.confidence
                )
            }
            return VisionSubjectClassificationResolver.resolve(
                candidates: candidates
            )
        }
        return try await withTaskCancellationHandler {
            try await classificationTask.value
        } onCancel: {
            classificationTask.cancel()
        }
    }
}

enum VisionSubjectClassificationResolver {
    static func resolve(
        candidates: [VisionClassificationCandidate],
        confidenceThreshold: Float = MerianConfig.visionConfidenceThreshold,
        marginThreshold: Float = MerianConfig.visionMarginThreshold
    ) -> VisionSubjectClassification {
        guard let top = candidates.first,
              top.confidence >= confidenceThreshold else {
            return VisionSubjectClassification(
                category: nil,
                candidates: candidates
            )
        }
        if candidates.count >= 2,
           top.confidence - candidates[1].confidence < marginThreshold {
            return VisionSubjectClassification(
                category: nil,
                candidates: candidates
            )
        }
        return VisionSubjectClassification(
            category: LocalSubjectCategory(identifier: top.identifier),
            candidates: candidates
        )
    }
}

enum LocalSubjectCategory: String, CaseIterable, Sendable {
    case avian
    case arthropod
    case arachnid
    case fungal
    case floweringPlant
    case tree
    case succulent
    case botanical
    case reptile
    case amphibian
    case fish
    case mammal

    init?(identifier: String) {
        let tokens = Set(
            identifier.lowercased()
                .components(
                    separatedBy: CharacterSet.alphanumerics.inverted
                )
                .filter { !$0.isEmpty }
        )
        for category in Self.allCases where category.identifierTerms.contains(
            where: {
                Self.matches(identifierTerm: $0, tokens: tokens)
            }
        ) {
            self = category
            return
        }
        return nil
    }

    var phraseSeries: [String] {
        switch self {
        case .avian:
            return [
                "Avian form visible",
                "Examining feather pattern",
                "Studying bill shape",
                "Tracing wing proportions",
                "Comparing tail outline"
            ]
        case .arthropod:
            return [
                "Arthropod form visible",
                "Examining wing veins",
                "Studying body segments",
                "Tracing appendage shape",
                "Comparing limb proportions"
            ]
        case .arachnid:
            return [
                "Arachnid form visible",
                "Examining leg arrangement",
                "Studying body segments",
                "Tracing surface markings",
                "Comparing body proportions"
            ]
        case .fungal:
            return [
                "Fungal form visible",
                "Examining cap shape",
                "Studying gill structure",
                "Tracing surface texture",
                "Comparing underside pattern"
            ]
        case .floweringPlant:
            return [
                "Flowering form visible",
                "Examining petal layout",
                "Studying flower structure",
                "Tracing bloom pattern",
                "Reviewing center markings"
            ]
        case .tree:
            return [
                "Tree form visible",
                "Examining bark texture",
                "Studying leaf shape",
                "Tracing branch structure",
                "Comparing canopy outline"
            ]
        case .succulent:
            return [
                "Succulent form visible",
                "Examining spine pattern",
                "Studying stem shape",
                "Tracing surface texture",
                "Reviewing rib contours"
            ]
        case .botanical:
            return [
                "Plant form visible",
                "Examining leaf shape",
                "Studying vein pattern",
                "Tracing growth structure",
                "Comparing edge contours"
            ]
        case .reptile:
            return [
                "Reptile form visible",
                "Examining scale pattern",
                "Studying body shape",
                "Tracing dorsal markings",
                "Reviewing head profile"
            ]
        case .amphibian:
            return [
                "Amphibian form visible",
                "Examining skin texture",
                "Studying body shape",
                "Tracing surface markings",
                "Comparing limb proportions"
            ]
        case .fish:
            return [
                "Aquatic form visible",
                "Examining fin shape",
                "Studying body proportions",
                "Tracing side markings",
                "Reviewing tail profile"
            ]
        case .mammal:
            return [
                "Mammal form visible",
                "Examining coat pattern",
                "Studying body proportions",
                "Tracing facial markings",
                "Reviewing limb proportions"
            ]
        }
    }

    private var identifierTerms: [String] {
        switch self {
        case .avian:
            return ["bird", "avian", "raptor", "songbird", "waterfowl", "owl"]
        case .arthropod:
            return [
                "insect", "arthropod", "butterfly", "moth", "bee", "beetle",
                "fly", "ant", "wasp", "dragonfly", "cricket", "grasshopper"
            ]
        case .arachnid:
            return ["spider", "arachnid", "scorpion", "tick", "mite"]
        case .fungal:
            return ["mushroom", "fungal", "fungi", "fungus", "lichen"]
        case .floweringPlant:
            return ["flower", "flowering", "blossom", "bloom"]
        case .tree:
            return ["tree", "conifer", "palm"]
        case .succulent:
            return ["cactus", "cacti", "cactaceae", "succulent"]
        case .botanical:
            return [
                "plant", "leaf", "leaves", "vegetation", "shrub", "grass",
                "fern", "moss", "algae", "vine"
            ]
        case .reptile:
            return [
                "reptile", "snake", "lizard", "turtle", "crocodile", "gecko"
            ]
        case .amphibian:
            return [
                "amphibian", "frog", "toad", "salamander", "newt", "caecilian"
            ]
        case .fish:
            return ["fish", "shark", "ray", "eel", "salmon", "trout"]
        case .mammal:
            return [
                "mammal", "dog", "cat", "deer", "fox", "bear", "rabbit",
                "squirrel", "raccoon", "rodent", "primate"
            ]
        }
    }

    private static func matches(
        identifierTerm: String,
        tokens: Set<String>
    ) -> Bool {
        if tokens.contains(identifierTerm)
            || tokens.contains(identifierTerm + "s")
            || tokens.contains(identifierTerm + "es") {
            return true
        }
        guard identifierTerm.hasSuffix("y") else { return false }
        return tokens.contains(String(identifierTerm.dropLast()) + "ies")
    }
}
