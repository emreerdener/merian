import Foundation

/// Represents a guided prompt shown in Describe mode to help users
/// systematically identify a subject.
///
/// Contains a human-readable question and a set of predefined contextual tags
/// that, when selected, append optimized natural language into the user's notes.
struct GuidedQuestion: Hashable {
    struct Tag: Hashable {
        let tagId: String
        let label: String
        /// Optimized natural-language fragment written into freeText.
        let aiText: String
        let defaultWeight: Int
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
    // 1. THE CORE SUBJECT
    GuidedQuestion(
        prompt: "What did you find?",
        tags: [
            .init(tagId: "subj_bird", label: "A bird", aiText: "a bird", defaultWeight: 100),
            .init(tagId: "subj_insec", label: "An insect", aiText: "an insect", defaultWeight: 90),
            .init(tagId: "subj_spid", label: "A spider", aiText: "a spider or arachnid", defaultWeight: 80),
            .init(tagId: "subj_rept", label: "A reptile", aiText: "a reptile or amphibian", defaultWeight: 70),
            .init(tagId: "subj_plan", label: "A plant", aiText: "a plant or flower", defaultWeight: 60),
            .init(tagId: "subj_mush", label: "A mushroom", aiText: "a mushroom or fungus", defaultWeight: 50),
            .init(tagId: "subj_mamm", label: "A small mammal", aiText: "a small mammal", defaultWeight: 40),
            .init(tagId: "subj_fish", label: "A fish", aiText: "a fish or aquatic creature", defaultWeight: 30),
            .init(tagId: "subj_othr", label: "Other", aiText: "an unlisted subject", defaultWeight: 20)
        ]
    ),
    
    // 2. THE MACRO SCENE
    GuidedQuestion(
        prompt: "What was the surrounding environment like?",
        tags: [
            .init(tagId: "env_sunny", label: "Sunny & dry", aiText: "in a sunny, dry environment", defaultWeight: 0),
            .init(tagId: "env_damp", label: "Damp/after rain", aiText: "in a damp habitat after recent rain", defaultWeight: 0),
            .init(tagId: "env_night", label: "At night", aiText: "observed at night or in low light", defaultWeight: 0),
            .init(tagId: "env_forest", label: "Dense forest", aiText: "within dense forest or woodland", defaultWeight: 0),
            .init(tagId: "env_dryland", label: "Open dry land", aiText: "in open, arid, or grassland habitat", defaultWeight: 0)
        ]
    ),
    
    // 3. THE MICRO LOCATION
    GuidedQuestion(
        prompt: "Where exactly did you spot it?",
        tags: [
            .init(tagId: "loc_wood", label: "On wood", aiText: "resting on wood or bark", defaultWeight: 0),
            .init(tagId: "loc_water", label: "Near water", aiText: "found near or in water", defaultWeight: 0),
            .init(tagId: "loc_rock", label: "Under a rock", aiText: "sheltering beneath a rock", defaultWeight: 0),
            .init(tagId: "loc_leaf", label: "On a leaf", aiText: "perched on a leaf surface", defaultWeight: 0),
            .init(tagId: "loc_soil", label: "In soil", aiText: "found in or on bare soil", defaultWeight: 0),
            .init(tagId: "loc_tree", label: "High in tree", aiText: "observed high up in a tree canopy", defaultWeight: 0)
        ]
    ),
    
    // 4. GENERAL SIZE & SHAPE
    GuidedQuestion(
        prompt: "Roughly how big was it?",
        tags: [
            .init(tagId: "size_tiny", label: "Tiny (< 5mm)", aiText: "very small, under 5mm in length", defaultWeight: 0),
            .init(tagId: "size_coin", label: "Coin-sized", aiText: "roughly coin-sized", defaultWeight: 0),
            .init(tagId: "size_palm", label: "Palm-sized", aiText: "approximately palm-sized", defaultWeight: 0),
            .init(tagId: "size_hand", label: "Larger than a hand", aiText: "larger than a human hand", defaultWeight: 0)
        ]
    ),
    GuidedQuestion(
        prompt: "How would you describe its overall shape?",
        tags: [
            .init(tagId: "shape_long", label: "Elongated", aiText: "with an elongated, slender body", defaultWeight: 0),
            .init(tagId: "shape_round", label: "Round/oval", aiText: "with a round or oval body", defaultWeight: 0),
            .init(tagId: "shape_flat", label: "Flattened", aiText: "noticeably flat or disc-shaped", defaultWeight: 0),
            .init(tagId: "shape_coil", label: "Coiled", aiText: "coiled or curled when observed", defaultWeight: 0)
        ]
    ),
    
    // 5. SPECIFIC DETAILS
    GuidedQuestion(
        prompt: "Did you notice any distinct features, like wings or a shell?",
        tags: [
            .init(tagId: "det_shell", label: "Hard shell", aiText: "with a hard protective shell", defaultWeight: 0),
            .init(tagId: "det_wings", label: "Wings", aiText: "with clearly visible wings", defaultWeight: 0),
            .init(tagId: "det_feather", label: "Feathers", aiText: "covered in feathers", defaultWeight: 0),
            .init(tagId: "det_antenna", label: "Long antennae", aiText: "with notably long antennae", defaultWeight: 0),
            .init(tagId: "det_scale", label: "Scaly skin", aiText: "with scaly or rough skin", defaultWeight: 0),
            .init(tagId: "det_legs", label: "Many legs", aiText: "with many clearly visible legs", defaultWeight: 0)
        ]
    ),
    GuidedQuestion(
        prompt: "Did it have any distinct colors or patterns?",
        tags: [
            .init(tagId: "pat_irid", label: "Iridescent", aiText: "with iridescent, shifting coloring", defaultWeight: 0),
            .init(tagId: "pat_camo", label: "Camouflaged", aiText: "camouflaged to blend with surroundings", defaultWeight: 0),
            .init(tagId: "pat_solid", label: "Vivid solid color", aiText: "a single vivid, solid color", defaultWeight: 0),
            .init(tagId: "pat_dark", label: "Dark + markings", aiText: "dark-bodied with contrasting markings", defaultWeight: 0),
            .init(tagId: "pat_stripe", label: "Striped or spotted", aiText: "with distinct stripes or spots", defaultWeight: 0)
        ]
    ),
    
    // 6. THE ACTION
    GuidedQuestion(
        prompt: "What was it doing when you observed it?",
        tags: [
            .init(tagId: "act_still", label: "Motionless", aiText: "completely still when observed", defaultWeight: 0),
            .init(tagId: "act_fast", label: "Fast moving", aiText: "moving quickly when disturbed", defaultWeight: 0),
            .init(tagId: "act_feed", label: "Feeding", aiText: "actively feeding", defaultWeight: 0),
            .init(tagId: "act_burrow", label: "Burrowing", aiText: "burrowing into the substrate", defaultWeight: 0),
            .init(tagId: "act_sound", label: "Making sounds", aiText: "producing audible sounds", defaultWeight: 0)
        ]
    ),
    GuidedQuestion(
        prompt: "Was it alone, or in a group?",
        tags: [
            .init(tagId: "soc_sol", label: "Solitary", aiText: "observed alone with none nearby", defaultWeight: 0),
            .init(tagId: "soc_pair", label: "Small group", aiText: "part of a small cluster or pair", defaultWeight: 0),
            .init(tagId: "soc_swarm", label: "Large colony", aiText: "part of a large colony or swarm", defaultWeight: 0)
        ]
    ),
    
    // 7. FINAL OPEN-ENDED PROMPT
    GuidedQuestion(
        prompt: "Are there any other interesting details you noticed?",
        tags: []
    )
]
