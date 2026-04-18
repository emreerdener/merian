import Foundation

/// Represents a guided prompt shown in Describe mode to help users
/// systematically identify a subject.
///
/// Contains a human-readable question and a set of predefined contextual tags
/// that, when selected, append optimized natural language into the user's notes.
struct GuidedQuestion: Hashable {
    struct Tag: Hashable {
        let label: String
        /// Optimized natural-language fragment written into freeText.
        let aiText: String
    }
    let prompt: String
    let tags: [Tag]
}

/// The global, static list of curated identification prompts.
///
/// These questions progress sequentially from broad categorization
/// (e.g., "What did you see?") to specific morphology and environmental
/// context, acting as a structured interview for species identification.
let guidedQuestions: [GuidedQuestion] = [
    GuidedQuestion(
        prompt: "What did you see?",
        tags: [
            .init(label: "A bird", aiText: "a bird"),
            .init(label: "An insect", aiText: "an insect"),
            .init(label: "A spider", aiText: "a spider or arachnid"),
            .init(label: "A reptile", aiText: "a reptile or amphibian"),
            .init(label: "A plant", aiText: "a plant or flower"),
            .init(label: "A mushroom", aiText: "a mushroom or fungus"),
            .init(label: "A small mammal", aiText: "a small mammal"),
            .init(label: "A fish", aiText: "a fish or aquatic creature")
        ]
    ),
    GuidedQuestion(
        prompt: "Where exactly did you find it?",
        tags: [
            .init(label: "On wood", aiText: "resting on wood or bark"),
            .init(label: "Near water", aiText: "found near or in water"),
            .init(label: "Under a rock", aiText: "sheltering beneath a rock"),
            .init(label: "On a leaf", aiText: "perched on a leaf surface"),
            .init(label: "In soil", aiText: "found in or on bare soil"),
            .init(label: "High in tree", aiText: "observed high up in a tree canopy")
        ]
    ),
    GuidedQuestion(
        prompt: "How large was it?",
        tags: [
            .init(label: "Tiny (< 5mm)", aiText: "very small, under 5mm in length"),
            .init(label: "Coin-sized", aiText: "roughly coin-sized"),
            .init(label: "Palm-sized", aiText: "approximately palm-sized"),
            .init(label: "Larger than a hand", aiText: "larger than a human hand")
        ]
    ),
    GuidedQuestion(
        prompt: "What was it doing?",
        tags: [
            .init(label: "Motionless", aiText: "completely still when observed"),
            .init(label: "Fast moving", aiText: "moving quickly when disturbed"),
            .init(label: "Feeding", aiText: "actively feeding"),
            .init(label: "Burrowing", aiText: "burrowing into the substrate"),
            .init(label: "Making sounds", aiText: "producing audible sounds")
        ]
    ),
    GuidedQuestion(
        prompt: "Any striking colors or patterns?",
        tags: [
            .init(label: "Iridescent", aiText: "with iridescent, shifting coloring"),
            .init(label: "Camouflaged", aiText: "camouflaged to blend with surroundings"),
            .init(label: "Vivid solid color", aiText: "a single vivid, solid color"),
            .init(label: "Dark + markings", aiText: "dark-bodied with contrasting markings"),
            .init(label: "Striped or spotted", aiText: "with distinct stripes or spots")
        ]
    ),
    GuidedQuestion(
        prompt: "Any distinct features — wings, shell, legs?",
        tags: [
            .init(label: "Hard shell", aiText: "with a hard protective shell"),
            .init(label: "Wings", aiText: "with clearly visible wings"),
            .init(label: "Feathers", aiText: "covered in feathers"),
            .init(label: "Long antennae", aiText: "with notably long antennae"),
            .init(label: "Scaly skin", aiText: "with scaly or rough skin"),
            .init(label: "Many legs", aiText: "with many clearly visible legs")
        ]
    ),
    GuidedQuestion(
        prompt: "Describe its overall body shape.",
        tags: [
            .init(label: "Elongated", aiText: "with an elongated, slender body"),
            .init(label: "Round/oval", aiText: "with a round or oval body"),
            .init(label: "Flattened", aiText: "noticeably flat or disc-shaped"),
            .init(label: "Coiled", aiText: "coiled or curled when observed")
        ]
    ),
    GuidedQuestion(
        prompt: "Was it alone or with others?",
        tags: [
            .init(label: "Solitary", aiText: "observed alone with none nearby"),
            .init(label: "Small group", aiText: "part of a small cluster or pair"),
            .init(label: "Large colony", aiText: "part of a large colony or swarm")
        ]
    ),
    GuidedQuestion(
        prompt: "What was the environment like?",
        tags: [
            .init(label: "Sunny & dry", aiText: "in a sunny, dry environment"),
            .init(label: "Damp/after rain", aiText: "in a damp habitat after recent rain"),
            .init(label: "At night", aiText: "observed at night or in low light"),
            .init(label: "Dense forest", aiText: "within dense forest or woodland"),
            .init(label: "Open dry land", aiText: "in open, arid, or grassland habitat")
        ]
    )
]
