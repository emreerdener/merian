import Foundation
import MapKit

struct ExploreMapCachedResponse {
    let response: ExploreMapPointsResponse
    let speciesCategories: Set<ExploreMapSpeciesCategory>
    let mediaTypes: Set<ExploreMediaKind>
    let isFresh: Bool
}

struct ExploreMapResponseCache {
    private struct Entry {
        var region: MKCoordinateRegion
        var speciesCategories: Set<ExploreMapSpeciesCategory>
        var mediaTypes: Set<ExploreMediaKind>
        var response: ExploreMapPointsResponse
        var lastAccessedAt: Date

        var itemCount: Int {
            response.posts.count + response.clusters.count
        }
    }

    private let maxRegions: Int
    private let maxItems: Int
    private let freshTTL: TimeInterval
    private var entries: [Entry] = []

    init(
        maxRegions: Int = 8,
        maxItems: Int = 1_400,
        freshTTL: TimeInterval = 90
    ) {
        self.maxRegions = maxRegions
        self.maxItems = maxItems
        self.freshTTL = freshTTL
    }

    mutating func removeAll() {
        entries.removeAll()
    }

    mutating func cachedResponse(
        for region: MKCoordinateRegion,
        speciesCategories: Set<ExploreMapSpeciesCategory>,
        mediaTypes: Set<ExploreMediaKind>,
        now: Date
    ) -> ExploreMapCachedResponse? {
        guard let index = responseIndex(
            for: region,
            speciesCategories: speciesCategories,
            mediaTypes: mediaTypes
        ) else {
            return nil
        }

        let entry = entries[index]
        entries[index].lastAccessedAt = now
        prune(around: region)

        return ExploreMapCachedResponse(
            response: entry.response,
            speciesCategories: entry.speciesCategories,
            mediaTypes: entry.mediaTypes,
            isFresh: now.timeIntervalSince(entry.lastAccessedAt) < freshTTL
        )
    }

    mutating func store(
        _ response: ExploreMapPointsResponse,
        for region: MKCoordinateRegion,
        speciesCategories: Set<ExploreMapSpeciesCategory>,
        mediaTypes: Set<ExploreMediaKind>,
        now: Date
    ) {
        let entry = Entry(
            region: region,
            speciesCategories: speciesCategories,
            mediaTypes: mediaTypes,
            response: response,
            lastAccessedAt: now
        )

        if let index = responseIndex(
            for: region,
            speciesCategories: speciesCategories,
            mediaTypes: mediaTypes
        ) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }

        prune(around: region)
    }

    private func responseIndex(
        for region: MKCoordinateRegion,
        speciesCategories: Set<ExploreMapSpeciesCategory>,
        mediaTypes: Set<ExploreMediaKind>
    ) -> Int? {
        entries.indices
            .filter {
                regionsAreCompatible(entries[$0].region, region)
                    && entries[$0].speciesCategories == speciesCategories
                    && entries[$0].mediaTypes == mediaTypes
            }
            .max(by: { entries[$0].lastAccessedAt < entries[$1].lastAccessedAt })
    }

    private mutating func prune(around region: MKCoordinateRegion) {
        let expandedRegion = region.expandedForExploreMap(by: 2.5)
        entries.removeAll { !expandedRegion.containsForExploreMap($0.region.center) }
        entries.sort { $0.lastAccessedAt > $1.lastAccessedAt }

        if entries.count > maxRegions {
            entries = Array(entries.prefix(maxRegions))
        }

        var totalItems = entries.reduce(0) { $0 + $1.itemCount }
        while totalItems > maxItems, let lastEntry = entries.last {
            entries.removeLast()
            totalItems -= lastEntry.itemCount
        }
    }

    private func regionsAreCompatible(
        _ lhs: MKCoordinateRegion,
        _ rhs: MKCoordinateRegion
    ) -> Bool {
        let latitudeThreshold = max(
            max(lhs.span.latitudeDelta, rhs.span.latitudeDelta) * 0.12,
            0.01
        )
        let longitudeThreshold = max(
            max(lhs.span.longitudeDelta, rhs.span.longitudeDelta) * 0.12,
            0.01
        )
        let latitudeSpanRatio = max(lhs.span.latitudeDelta, rhs.span.latitudeDelta)
            / max(min(lhs.span.latitudeDelta, rhs.span.latitudeDelta), 0.000_01)
        let longitudeSpanRatio = max(lhs.span.longitudeDelta, rhs.span.longitudeDelta)
            / max(min(lhs.span.longitudeDelta, rhs.span.longitudeDelta), 0.000_01)

        return abs(lhs.center.latitude - rhs.center.latitude) <= latitudeThreshold
            && wrappedLongitudeDelta(lhs.center.longitude, rhs.center.longitude) <= longitudeThreshold
            && latitudeSpanRatio <= 1.18
            && longitudeSpanRatio <= 1.18
    }

    private func wrappedLongitudeDelta(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }
}
