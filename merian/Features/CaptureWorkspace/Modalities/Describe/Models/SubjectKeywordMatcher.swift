import Foundation

struct SubjectKeywordMatcher {
    private static let keywords: [String: String] = [
        // Birds
        "bird": "subj_bird", "sparrow": "subj_bird", "hawk": "subj_bird",
        "eagle": "subj_bird", "robin": "subj_bird", "pigeon": "subj_bird",
        "duck": "subj_bird", "goose": "subj_bird", "owl": "subj_bird",
        // Insects
        "insect": "subj_insec", "beetle": "subj_insec", "butterfly": "subj_insec",
        "moth": "subj_insec", "bee": "subj_insec", "wasp": "subj_insec",
        "fly": "subj_insec", "dragonfly": "subj_insec", "ant": "subj_insec",
        "bug": "subj_insec", "spider": "subj_spid", "arachnid": "subj_spid",
        "tarantula": "subj_spid", "scorpion": "subj_spid", "tick": "subj_spid", "mite": "subj_spid",
        
        // Reptiles & Amphibians
        "reptile": "subj_rept", "amphibian": "subj_rept", "snake": "subj_rept", 
        "lizard": "subj_rept", "turtle": "subj_rept", "tortoise": "subj_rept", 
        "frog": "subj_rept", "toad": "subj_rept", "salamander": "subj_rept",
        
        // Mushrooms
        "mushroom": "subj_mush", "fungus": "subj_mush", "fungi": "subj_mush", 
        "toadstool": "subj_mush", "puffball": "subj_mush",
        
        // Mammals
        "mammal": "subj_mamm", "rodent": "subj_mamm", "squirrel": "subj_mamm", 
        "rabbit": "subj_mamm", "hare": "subj_mamm", "raccoon": "subj_mamm", 
        "skunk": "subj_mamm", "opossum": "subj_mamm", "mouse": "subj_mamm", "rat": "subj_mamm",
        
        // Fish
        "fish": "subj_fish", "shark": "subj_fish", "stingray": "subj_fish", "manta": "subj_fish",
        "eel": "subj_fish", "trout": "subj_fish", "salmon": "subj_fish",
        
        // Plants
        "plant": "subj_plan", "tree": "subj_plan", "flower": "subj_plan",
        "shrub": "subj_plan", "bush": "subj_plan", "fern": "subj_plan",
        "moss": "subj_plan", "grass": "subj_plan", "weed": "subj_plan"
    ]
    
    static func infer(from text: String) -> String? {
        let words = text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
        for word in words {
            if let match = keywords[word] { return match }
        }
        return nil
    }
}
