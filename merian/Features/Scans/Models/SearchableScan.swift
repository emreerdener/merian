import Foundation

// MARK: - Concurrency DTO
struct SearchableScan: Sendable {
    // MARK: - Safe Properties
    let id: String
    let searchString: String
    let ecologyType: String
    let kingdom: String
    let className: String

    var categoryBucket: SearchCategoryBucket {
        SearchCategoryBucket(kingdom: kingdom, className: className)
    }
}

enum SearchCategoryBucket: String, CaseIterable, Sendable {
    case plants
    case fungi
    case insects
    case birds
    case mammals
    case reptiles
    case other

    init(kingdom: String, className: String) {
        if kingdom == "plantae" {
            self = .plants
        } else if kingdom == "fungi" {
            self = .fungi
        } else if className == "insecta" || className == "entognatha" || className == "arachnida" {
            self = .insects
        } else if className == "aves" {
            self = .birds
        } else if className == "mammalia" {
            self = .mammals
        } else if className == "reptilia" || className == "squamata" || className == "amphibia" {
            self = .reptiles
        } else {
            self = .other
        }
    }
}

struct SearchIndexSnapshot: Sendable {
    struct IndexedTerms: Sendable {
        let words: [String]
        let bigrams: [String]
        let trigrams: [String]
    }

    static let empty = SearchIndexSnapshot()

    private(set) var documentsById: [String: SearchableScan] = [:]
    private(set) var wordIndex: [String: [String]] = [:]
    private(set) var bigramIndex: [String: [String]] = [:]
    private(set) var trigramIndex: [String: [String]] = [:]
    private(set) var categoryIndex: [SearchCategoryBucket: [String]] = [:]
    private(set) var allDocumentIDs: [String] = []

    var isEmpty: Bool { documentsById.isEmpty }
    var count: Int { documentsById.count }

    init(searchableScans: [SearchableScan] = []) {
        guard !searchableScans.isEmpty else { return }

        documentsById.reserveCapacity(searchableScans.count)
        allDocumentIDs.reserveCapacity(searchableScans.count)

        for scan in searchableScans {
            upsert(scan)
        }
    }

    func ids(matching categoryMatch: String) -> [String] {
        switch categoryMatch.lowercased() {
        case "all":
            return allDocumentIDs
        case "plants":
            return categoryIndex[.plants] ?? []
        case "fungi":
            return categoryIndex[.fungi] ?? []
        case "insects":
            return categoryIndex[.insects] ?? []
        case "birds":
            return categoryIndex[.birds] ?? []
        case "mammals":
            return categoryIndex[.mammals] ?? []
        case "reptiles":
            return categoryIndex[.reptiles] ?? []
        case "other":
            return categoryIndex[.other] ?? []
        default:
            return []
        }
    }

    func candidateIDs(matching token: String) -> [String] {
        let normalizedToken = SearchIndexTokenizer.normalizedQueryToken(from: token)
        guard !normalizedToken.isEmpty else { return [] }

        switch normalizedToken.count {
        case 1:
            // Single-character queries are inherently broad. Fall back to verification on the
            // filtered candidate set rather than exploding the index with one-character grams.
            return allDocumentIDs
        case 2:
            if let exactBigramMatches = bigramIndex[normalizedToken] {
                return exactBigramMatches
            }
            return wordIndex[normalizedToken] ?? []
        default:
            let grams = SearchIndexTokenizer.trigrams(from: normalizedToken)
            guard !grams.isEmpty else { return wordIndex[normalizedToken] ?? [] }

            let postingLists = grams.compactMap { trigramIndex[$0] }
            guard postingLists.count == grams.count else { return [] }
            return Self.intersect(postingLists)
        }
    }

    func removing(ids: Set<String>) -> SearchIndexSnapshot {
        guard !ids.isEmpty else { return self }
        var copy = self
        for id in ids {
            copy.remove(id: id)
        }
        return copy
    }

    func upserting(_ scans: [SearchableScan]) -> SearchIndexSnapshot {
        guard !scans.isEmpty else { return self }
        var copy = self
        for scan in scans {
            copy.upsert(scan)
        }
        return copy
    }

    private mutating func upsert(_ scan: SearchableScan) {
        if documentsById[scan.id] != nil {
            remove(id: scan.id)
        }

        documentsById[scan.id] = scan
        allDocumentIDs.append(scan.id)

        let terms = SearchIndexTokenizer.indexedTerms(for: scan.searchString)
        var updatedWordIndex = wordIndex
        var updatedBigramIndex = bigramIndex
        var updatedTrigramIndex = trigramIndex
        var updatedCategoryIndex = categoryIndex

        Self.append(scan.id, to: &updatedWordIndex, terms: terms.words)
        Self.append(scan.id, to: &updatedBigramIndex, terms: terms.bigrams)
        Self.append(scan.id, to: &updatedTrigramIndex, terms: terms.trigrams)
        updatedCategoryIndex[scan.categoryBucket, default: []].append(scan.id)

        wordIndex = updatedWordIndex
        bigramIndex = updatedBigramIndex
        trigramIndex = updatedTrigramIndex
        categoryIndex = updatedCategoryIndex
    }

    private mutating func remove(id: String) {
        guard let removedScan = documentsById.removeValue(forKey: id) else { return }

        allDocumentIDs.removeAll { $0 == id }

        let terms = SearchIndexTokenizer.indexedTerms(for: removedScan.searchString)
        var updatedWordIndex = wordIndex
        var updatedBigramIndex = bigramIndex
        var updatedTrigramIndex = trigramIndex
        var updatedCategoryIndex = categoryIndex

        Self.remove(id, from: &updatedWordIndex, terms: terms.words)
        Self.remove(id, from: &updatedBigramIndex, terms: terms.bigrams)
        Self.remove(id, from: &updatedTrigramIndex, terms: terms.trigrams)
        Self.remove(id, from: &updatedCategoryIndex, category: removedScan.categoryBucket)

        wordIndex = updatedWordIndex
        bigramIndex = updatedBigramIndex
        trigramIndex = updatedTrigramIndex
        categoryIndex = updatedCategoryIndex
    }

    private static func append(_ id: String, to index: inout [String: [String]], terms: [String]) {
        for term in terms {
            index[term, default: []].append(id)
        }
    }

    private static func remove(_ id: String, from index: inout [String: [String]], terms: [String]) {
        for term in terms {
            guard var postings = index[term] else { continue }
            postings.removeAll { $0 == id }
            if postings.isEmpty {
                index.removeValue(forKey: term)
            } else {
                index[term] = postings
            }
        }
    }

    private static func remove(_ id: String, from index: inout [SearchCategoryBucket: [String]], category: SearchCategoryBucket) {
        guard var postings = index[category] else { return }
        postings.removeAll { $0 == id }
        if postings.isEmpty {
            index.removeValue(forKey: category)
        } else {
            index[category] = postings
        }
    }

    private static func intersect(_ postingLists: [[String]]) -> [String] {
        guard let smallest = postingLists.min(by: { $0.count < $1.count }) else { return [] }

        var intersection = Set(smallest)
        for postings in postingLists where postings != smallest {
            intersection.formIntersection(postings)
            if intersection.isEmpty { return [] }
        }

        return Array(intersection)
    }
}

enum SearchIndexTokenizer {
    private static let separators = CharacterSet.alphanumerics.inverted

    static func indexedTerms(for searchString: String) -> SearchIndexSnapshot.IndexedTerms {
        let tokens = uniqueTokens(from: searchString)

        var bigrams = Set<String>()
        var trigrams = Set<String>()

        for token in tokens {
            if token.count >= 2 {
                bigrams.formUnion(ngrams(from: token, length: 2))
            }
            if token.count >= 3 {
                trigrams.formUnion(ngrams(from: token, length: 3))
            }
        }

        return SearchIndexSnapshot.IndexedTerms(
            words: Array(tokens),
            bigrams: Array(bigrams),
            trigrams: Array(trigrams)
        )
    }

    static func queryTokens(from text: String) -> [String] {
        let rawTokens = text
            .lowercased()
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }

        var seen = Set<String>()
        var orderedTokens: [String] = []
        orderedTokens.reserveCapacity(rawTokens.count)

        for token in rawTokens where seen.insert(token).inserted {
            orderedTokens.append(token)
        }

        return orderedTokens
    }

    static func normalizedQueryToken(from token: String) -> String {
        token.lowercased()
    }

    static func trigrams(from token: String) -> [String] {
        ngrams(from: token, length: 3)
    }

    private static func uniqueTokens(from text: String) -> Set<String> {
        Set(
            text
                .lowercased()
                .components(separatedBy: separators)
                .filter { !$0.isEmpty }
        )
    }

    private static func ngrams(from token: String, length: Int) -> [String] {
        guard length > 0 else { return [] }

        let scalars = Array(token)
        guard scalars.count >= length else { return [] }

        var grams = Set<String>()
        grams.reserveCapacity(scalars.count - length + 1)

        for index in 0...(scalars.count - length) {
            grams.insert(String(scalars[index..<(index + length)]))
        }

        return Array(grams)
    }
}
