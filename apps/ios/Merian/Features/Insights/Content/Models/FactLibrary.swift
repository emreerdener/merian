import SwiftUI

/// Defines a structured fun fact displayed during analysis or loading states.
struct InsightFact {
    let text: String
    let category: String
}

/// A centralized repository of scientific and biological facts.
/// Provides a pre-computed `longestFact` to assist with smooth UI sizing constraints.
struct FactLibrary {
    static let facts: [InsightFact] = [
        // MARK: - Original Facts
        InsightFact(text: "There are an estimated 8.7 million species on Earth. Fewer than 2 million have been formally described.", category: "BIODIVERSITY"),
        InsightFact(text: "A single oak tree can support over 500 species of insects, birds, and fungi.", category: "ECOLOGY"),
        InsightFact(text: "The world's largest known organism is a honey fungus in Oregon spanning over 2,385 acres underground.", category: "FUNGI"),
        InsightFact(text: "Butterflies taste with their feet — their sensory receptors are 200× more sensitive than the human tongue.", category: "BEHAVIOR"),
        InsightFact(text: "Plants can detect the saliva of caterpillars and trigger targeted chemical defences in response.", category: "BOTANY"),
        InsightFact(text: "Ants have colonized every continent except Antarctica, and have been doing so for over 130 million years.", category: "EVOLUTION"),
        InsightFact(text: "The bombardier beetle fires a boiling-hot chemical spray from its abdomen at 500 pulses per second.", category: "DEFENSE"),
        InsightFact(text: "A honeybee must visit roughly 2 million flowers and fly 55,000 miles to produce one pound of honey.", category: "INSECTS"),
        InsightFact(text: "Tardigrades survive the vacuum of space, temperatures from −272 °C to 151 °C, and radiation 1,000× lethal to humans.", category: "EXTREMOPHILES"),
        InsightFact(text: "Trees in a forest share carbon and nutrients through underground fungal networks — the 'Wood Wide Web.'", category: "ECOLOGY"),
        InsightFact(text: "Some jellyfish are considered biologically immortal — they revert to a juvenile state when old or stressed.", category: "MARINELIFE"),
        InsightFact(text: "The mantis shrimp has 16 types of photoreceptors. Humans have 3.", category: "SENSES"),
        InsightFact(text: "A single gram of forest soil can contain up to 1 billion bacteria from thousands of distinct species.", category: "MICROBIOLOGY"),
        InsightFact(text: "Over 90% of all land plant species have mycorrhizal fungi colonizing their roots.", category: "FUNGI"),
        InsightFact(text: "Each firefly species flashes a unique light-pulse pattern — its own private language for finding mates.", category: "BEHAVIOR"),
        InsightFact(text: "The pistol shrimp snaps its claw so fast it generates a cavitation bubble briefly hotter than the Sun's surface.", category: "MARINELIFE"),
        InsightFact(text: "Crows can recognize individual human faces and hold grudges against people who have wronged them.", category: "INTELLIGENCE"),
        InsightFact(text: "Hummingbirds are the only birds capable of sustained backward flight.", category: "BIRDS"),
        InsightFact(text: "Orchids are the largest family of flowering plants — comprising roughly 10% of all flower species on Earth.", category: "BOTANY"),
        InsightFact(text: "The blue whale's heart beats just 5–8 times per minute when diving and is roughly the size of a small car.", category: "MARINELIFE"),

        // MARK: - Mammals
        InsightFact(text: "Wombats are the only animals in the world known to produce cube-shaped poop, which prevents it from rolling away.", category: "MAMMALS"),
        InsightFact(text: "A cheetah can accelerate from 0 to 60 mph in just 3 seconds, using its tail as a rudder to steer during high-speed chases.", category: "MAMMALS"),
        InsightFact(text: "Koalas have fingerprints so remarkably similar to humans' that they have been known to confuse investigators at crime scenes.", category: "MAMMALS"),
        InsightFact(text: "Snow leopards are the only large cats that cannot roar. Instead, they purr, chuff, and meow.", category: "MAMMALS"),
        InsightFact(text: "Bats are the only mammals capable of true, sustained flight, and they make up roughly 20% of all mammal species.", category: "MAMMALS"),
        InsightFact(text: "Moose are surprisingly excellent swimmers. They can hold their breath for a full minute and dive up to 20 feet to eat aquatic plants.", category: "MAMMALS"),
        InsightFact(text: "Sloths have such a slow metabolism that it can take them up to a month to completely digest a single leaf.", category: "MAMMALS"),

        // MARK: - Marine & Aquatic Life
        InsightFact(text: "Octopuses have three hearts, nine brains, and blue blood. Two hearts pump blood to the gills, and one to the rest of the body.", category: "MARINELIFE"),
        InsightFact(text: "The Greenland shark has the longest known lifespan of all vertebrate species, estimated to live between 250 and 500 years.", category: "MARINELIFE"),
        InsightFact(text: "Male seahorses, not the females, carry eggs in a specialized brood pouch and give birth to the tiny seahorse fry.", category: "MARINELIFE"),
        InsightFact(text: "Corals are not plants; they are animals. A single coral branch is a colony made up of thousands of tiny animals called polyps.", category: "MARINELIFE"),
        InsightFact(text: "The tongue of an adult blue whale is so massive that it weighs as much as an entire elephant.", category: "MARINELIFE"),
        InsightFact(text: "To eat, a sea star extrudes its stomach out of its mouth, digests its prey outside its body, and then swallows its stomach back whole.", category: "MARINELIFE"),
        InsightFact(text: "Sharks do not have traditional scales; their skin is covered in tiny, tooth-like structures called dermal denticles.", category: "MARINELIFE"),
        InsightFact(text: "The colossal squid has the largest eyes in the animal kingdom, each roughly the size of a dinner plate.", category: "MARINELIFE"),

        // MARK: - Birds
        InsightFact(text: "The Arctic tern has the longest migration of any animal, flying from the Arctic to the Antarctic and back—up to 44,000 miles every year.", category: "BIRDS"),
        InsightFact(text: "The superb lyrebird of Australia can perfectly mimic almost any sound it hears, including chainsaws, camera shutters, and car alarms.", category: "BIRDS"),
        InsightFact(text: "Owls have specialized feathers with serrated edges that muffle the sound of air rushing over their wings, allowing them to fly silently.", category: "BIRDS"),
        InsightFact(text: "The peregrine falcon is the fastest animal on Earth, capable of reaching speeds over 240 mph (386 km/h) during a hunting dive.", category: "BIRDS"),
        InsightFact(text: "Great frigatebirds can sleep while flying, taking micro-naps that last just seconds while soaring over the ocean for months at a time.", category: "BIRDS"),
        InsightFact(text: "When threatened, hoatzin bird chicks drop from their tree nests into water, swimming to safety before climbing back up using claws on their wings.", category: "BIRDS"),
        InsightFact(text: "An ostrich's eye is physically larger than its entire brain.", category: "BIRDS"),

        // MARK: - Botany & Fungi
        InsightFact(text: "Bamboo is the fastest-growing plant on Earth. Certain species can grow up to 35 inches (90 cm) in a single day.", category: "BOTANY"),
        InsightFact(text: "Rafflesia arnoldii produces the world's largest individual flower, which can span 3 feet across and smells exactly like rotting meat.", category: "BOTANY"),
        InsightFact(text: "Venus flytraps have a 'memory.' A trap will only snap shut if a bug touches two distinct sensory hairs within 20 seconds of each other.", category: "BOTANY"),
        InsightFact(text: "Giant sequoia trees have fire-resistant bark up to 2 feet thick, and their cones actually require the heat of a wildfire to release seeds.", category: "BOTANY"),
        InsightFact(text: "Sunflowers naturally decontaminate soil by absorbing radioactive isotopes and heavy metals like lead and uranium.", category: "BOTANY"),
        InsightFact(text: "Coastal redwoods absorb up to 40% of their water intake directly from fog through their needles.", category: "BOTANY"),
        InsightFact(text: "Bumblebees unlock pollen from certain flowers by vibrating their flight muscles at a specific frequency, a process called 'buzz pollination'.", category: "BOTANY"),
        InsightFact(text: "The smell of cut grass is actually a chemical distress signal released by the plant, warning nearby vegetation of danger.", category: "BOTANY"),
        InsightFact(text: "Ophiocordyceps is a 'zombie fungus' that infects ants, hijacking their brains to make them climb plants before bursting from their heads.", category: "FUNGI"),
        InsightFact(text: "Fungi belong to their own kingdom of life and are genetically more closely related to animals than they are to plants.", category: "FUNGI"),

        // MARK: - Insects & Arachnids
        InsightFact(text: "Dragonflies are among the most efficient predators on Earth, catching their airborne prey with a success rate of over 95%.", category: "INSECTS"),
        InsightFact(text: "A single teaspoon of honey is the entire life's work of roughly 12 worker honeybees.", category: "INSECTS"),
        InsightFact(text: "When a caterpillar enters its chrysalis, it completely dissolves into an organic soup before reorganizing its cells into a butterfly.", category: "INSECTS"),
        InsightFact(text: "Spider silk is incredibly tough — by weight, it is five times stronger than steel and more flexible than nylon.", category: "ARACHNIDS"),
        InsightFact(text: "A single colony of leafcutter ants can consume as much vegetation in one day as a full-grown cow.", category: "INSECTS"),
        InsightFact(text: "Only female mosquitoes bite. They require the protein and iron found in blood to produce their eggs.", category: "INSECTS"),
        InsightFact(text: "A flea can jump up to 100 times its own height, experiencing G-forces roughly 100 times greater than the Apollo astronauts.", category: "INSECTS"),

        // MARK: - Amphibians & Reptiles
        InsightFact(text: "Axolotls can perfectly regenerate almost any part of their body, including limbs, spinal cord, heart, and parts of their brain.", category: "AMPHIBIANS"),
        InsightFact(text: "A chameleon's tongue can be up to twice the length of its body and accelerates from 0 to 60 mph in a hundredth of a second.", category: "REPTILES"),
        InsightFact(text: "Geckos can walk up smooth glass thanks to millions of microscopic hair-like structures on their toes that create van der Waals forces.", category: "REPTILES"),

        // MARK: - Extremophiles
        InsightFact(text: "Wood frogs can survive being completely frozen solid all winter. Their hearts stop beating, and they thaw out in the spring.", category: "EXTREMOPHILES"),
        InsightFact(text: "Naked mole-rats are virtually immune to cancer, can survive 18 minutes without oxygen, and feel no pain from acid.", category: "EXTREMOPHILES"),

        // MARK: - Ecology & Evolution
        InsightFact(text: "There are more trees on Earth (estimated at 3 trillion) than there are stars in the Milky Way galaxy.", category: "BIODIVERSITY"),
        InsightFact(text: "The Amazon Rainforest is home to an estimated 390 billion individual trees belonging to around 16,000 different species.", category: "BIODIVERSITY"),
        InsightFact(text: "Some species of cicadas emerge only every 13 or 17 years. These prime-number life cycles prevent predators from syncing with their emergence.", category: "EVOLUTION"),
        InsightFact(text: "Kelp forests are one of the fastest-growing ecosystems on Earth, with some giant kelp capable of growing up to 2 feet in a single day.", category: "ECOLOGY"),
        InsightFact(text: "Sharks have existed for over 400 million years, meaning they are older than trees and older than the rings of Saturn.", category: "EVOLUTION"),
        InsightFact(text: "Marine phytoplankton produce over 50% of the oxygen in our atmosphere, outproducing all the world's rainforests combined.", category: "ECOLOGY"),
        InsightFact(text: "Termites construct intricate mounds with built-in passive cooling systems that keep the interior climate perfectly stable.", category: "ECOLOGY"),
        InsightFact(text: "Nutrient-rich dust from the Sahara Desert is blown across the Atlantic Ocean every year, fertilizing the Amazon Rainforest.", category: "ECOLOGY"),
        InsightFact(text: "Beavers are ecosystem engineers; their dams create wetlands that filter water, reduce floods, and provide habitats for countless species.", category: "ECOLOGY"),
        InsightFact(text: "Some species of sea slugs can incorporate chloroplasts from the algae they eat, allowing them to photosynthesize like a plant.", category: "EVOLUTION"),

        // MARK: - Behavior & Intelligence
        InsightFact(text: "Slime molds lack a brain or nervous system, yet they can solve mazes and map out efficient transportation networks.", category: "INTELLIGENCE"),
        InsightFact(text: "Dung beetles are the only known animals to navigate using the faint glow of the Milky Way galaxy at night.", category: "BEHAVIOR"),
        InsightFact(text: "Sea otters hold paws while sleeping to keep from drifting apart in the ocean currents.", category: "BEHAVIOR"),
        InsightFact(text: "Vampire bats are the only mammals that survive entirely on blood, and they will share meals with hungry roost-mates to prevent starvation.", category: "BEHAVIOR"),
        InsightFact(text: "Dolphins give each other unique vocal whistles that act exactly like human names.", category: "INTELLIGENCE"),
        InsightFact(text: "Grizzly bears can remember the exact locations of specific food sources up to ten years after their last visit.", category: "INTELLIGENCE"),
        InsightFact(text: "The archerfish hunts by shooting a precisely calculated jet of water from its mouth to knock insects off overhanging leaves.", category: "BEHAVIOR"),
        InsightFact(text: "Pigeons are capable of recognizing themselves in a mirror and can even be trained to tell the difference between paintings by Monet and Picasso.", category: "INTELLIGENCE"),
        InsightFact(text: "Crocodiles often swallow heavy stones. These act as ballast to help them stay underwater longer and aid in digestion.", category: "BEHAVIOR"),
        InsightFact(text: "New Caledonian crows manufacture their own tools, intentionally bending twigs into hooks to extract grubs from logs.", category: "INTELLIGENCE"),
        InsightFact(text: "A snail can sleep for up to three years at a time to survive periods of extreme drought.", category: "BEHAVIOR"),
        InsightFact(text: "Sperm whales sleep vertically in the water, hanging completely motionless in pods just below the surface.", category: "BEHAVIOR"),

        // MARK: - Anatomy & Senses
        InsightFact(text: "A woodpecker's tongue is so long it wraps around its skull, acting as a built-in shock absorber when it pecks trees.", category: "ANATOMY"),
        InsightFact(text: "Elephants can communicate over long distances using low-frequency rumbles that travel through the ground, detected by their feet.", category: "SENSES"),
        InsightFact(text: "Hippos secrete a reddish, oily fluid that acts as a natural sunscreen, moisturizer, and antibiotic.", category: "ANATOMY"),
        InsightFact(text: "Platypuses don't have stomachs. Their esophagus connects directly to their intestines.", category: "ANATOMY"),
        InsightFact(text: "A giraffe's neck has exactly seven vertebrae—the same number as a human neck. They are just much larger.", category: "ANATOMY"),
        InsightFact(text: "Polar bears actually have jet-black skin underneath their white fur to better absorb heat from the sun.", category: "ANATOMY"),
        InsightFact(text: "A giraffe's tongue is up to 20 inches long and is dark blue-black to prevent it from getting sunburned while stripping leaves.", category: "ANATOMY"),
        InsightFact(text: "Platypuses don't have nipples; instead, they secrete milk through pores in their skin, and their babies lap it off the mother's fur.", category: "ANATOMY"),
        InsightFact(text: "Catfish have over 100,000 taste buds distributed all over their entire bodies, not just in their mouths.", category: "SENSES"),
        InsightFact(text: "Snakes 'smell' their surroundings by flicking their forked tongues to collect chemical particles from the air.", category: "SENSES"),

        // MARK: - Defense
        InsightFact(text: "The Texas horned lizard defends itself by shooting a stream of foul-tasting blood from the corners of its eyes at predators.", category: "DEFENSE"),
        InsightFact(text: "The mimic octopus can quickly contort its body and change its colors to impersonate toxic sea snakes, lionfish, and stingrays.", category: "DEFENSE"),
        InsightFact(text: "Acacia trees nibbled by giraffes emit ethylene gas, warning nearby trees to pump foul-tasting tannins into their leaves.", category: "DEFENSE"),
        InsightFact(text: "Playing possum isn't a conscious choice; opossums enter an involuntary coma-like state induced by extreme fear.", category: "DEFENSE")
    ]

    // Pre-computed for the invisible height anchor to avoid runtime max() calculations in the view.
    static let longestFact: String = facts.max(by: { $0.text.count < $1.text.count })?.text ?? ""
}

// MARK: - Fact Manager

/// Manages a shuffled deck of facts that persists across app launches to prevent repeats.
class FactManager: ObservableObject {
    static let shared = FactManager()

    @AppStorage("merian_fact_deck_indices") private var deckIndicesData: Data = Data()
    @AppStorage("merian_fact_deck_position") private var currentPosition: Int = 0
    
    @Published var currentIndex: Int = 0
    private var deck: [Int] = []

    private init() {
        // Initialization is completely free; heavy work is deferred
    }

    @MainActor
    func prepareIfNeeded() async {
        guard deck.isEmpty else { return }
        
        // Yield to ensure the view has completely finished its layout and render pass
        await Task.yield()
        
        loadOrShuffleDeck()
        self.currentIndex = currentPosition
    }

    private func loadOrShuffleDeck() {
        let expectedCount = FactLibrary.facts.count
        if let decoded = try? JSONDecoder().decode([Int].self, from: deckIndicesData), decoded.count == expectedCount {
            self.deck = decoded
        } else {
            self.deck = Array(0..<expectedCount).shuffled()
            if let encoded = try? JSONEncoder().encode(self.deck) {
                deckIndicesData = encoded
            }
            currentPosition = 0
        }
    }

    var currentFact: InsightFact {
        let safeIndex = deck.indices.contains(currentIndex) ? deck[currentIndex] : 0
        guard FactLibrary.facts.indices.contains(safeIndex) else { return FactLibrary.facts[0] }
        return FactLibrary.facts[safeIndex]
    }

    func advance() {
        currentIndex = (currentIndex + 1) % deck.count
        currentPosition = currentIndex
    }

    func retreat() {
        currentIndex = (currentIndex - 1 + deck.count) % deck.count
        currentPosition = currentIndex
    }
}
