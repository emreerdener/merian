import SwiftUI

/// Manages a shuffled deck of facts that persists across app launches to
/// prevent repeats. Live construction is resolved by Content Services.
@MainActor
final class FactManager: ObservableObject {
    static let shared = FactManager()

    @AppStorage("merian_fact_deck_indices") private var deckIndicesData = Data()
    @AppStorage("merian_fact_deck_position") private var currentPosition = 0

    @Published var currentIndex = 0
    private var deck: [Int] = []

    private init() {
        // Initialization is intentionally free; decoding and shuffling are
        // deferred until the mounted fact card requests them.
    }

    func prepareIfNeeded() async {
        guard deck.isEmpty else { return }

        // Yield so the card completes its first layout before deck work begins.
        await Task.yield()

        loadOrShuffleDeck()
        currentIndex = currentPosition
    }

    private func loadOrShuffleDeck() {
        let expectedCount = FactLibrary.facts.count
        if let decoded = try? JSONDecoder().decode(
            [Int].self,
            from: deckIndicesData
        ), decoded.count == expectedCount {
            deck = decoded
        } else {
            deck = Array(0..<expectedCount).shuffled()
            if let encoded = try? JSONEncoder().encode(deck) {
                deckIndicesData = encoded
            }
            currentPosition = 0
        }
    }

    var currentFact: InsightFact {
        let safeIndex = deck.indices.contains(currentIndex)
            ? deck[currentIndex]
            : 0
        guard FactLibrary.facts.indices.contains(safeIndex) else {
            return FactLibrary.facts[0]
        }
        return FactLibrary.facts[safeIndex]
    }

    func advance() {
        guard !deck.isEmpty else { return }
        currentIndex = (currentIndex + 1) % deck.count
        currentPosition = currentIndex
    }

    func retreat() {
        guard !deck.isEmpty else { return }
        currentIndex = (currentIndex - 1 + deck.count) % deck.count
        currentPosition = currentIndex
    }
}
