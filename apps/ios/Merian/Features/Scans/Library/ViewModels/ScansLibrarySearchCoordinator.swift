import SwiftData

/// Owns the mutable tasks, generation fences, and caches behind Library search.
///
/// `LocalScanRecord` values remain on the main actor. Only immutable snapshots and sort
/// primitives cross into detached work.
@MainActor
final class ScansLibrarySearchCoordinator {
    private static let rawSnapshotExtractionBatchSize = 128

    private let sharedPostID: @MainActor (_ scanID: String) -> String?
    private var records: [LocalScanRecord] = []
    private var searchIndexSnapshot = SearchIndexSnapshot.empty
    private var filterIndexSnapshot = ScanLibraryFilterIndexSnapshot.empty
    private var searchTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var filterIndexingTask: Task<Void, Never>?
    private var scanIndexByID: [String: Int] = [:]
    private var scanRecordByID: [String: LocalScanRecord] = [:]
    private var sortPrimitivesByID: [String: ScanSortPrimitive] = [:]
    private var allScanSortPrimitives: [ScanSortPrimitive] = []
    private var sortedAllScanIDsCache: [String: [String]] = [:]
    private var pendingReindexIDs: Set<String> = []
    private var cacheGeneration: UInt64 = 0
    private var filterIndexSnapshotGeneration: UInt64?
    private var onFilterIndexUpdated:
        (@MainActor (ScanLibraryFilterOptions, [String]) -> Void)?
    private var onSearchCompleted:
        (@MainActor ([LocalScanRecord], String) -> Void)?

    #if DEBUG
    var debugEventHandler: ((ScansLibrarySearchDebugEvent) -> Void)?
    private var debugSearchRequestID: UInt64 = 0
    private var debugCompletedSearchRequestID: UInt64?
    private var debugLastSearchCompletion: ScansLibrarySearchDebugEvent?
    #endif

    init(sharedPostID: @escaping @MainActor (_ scanID: String) -> String?) {
        self.sharedPostID = sharedPostID
    }

    func setHandlers(
        onFilterIndexUpdated: @escaping @MainActor (ScanLibraryFilterOptions, [String]) -> Void,
        onSearchCompleted: @escaping @MainActor ([LocalScanRecord], String) -> Void
    ) {
        self.onFilterIndexUpdated = onFilterIndexUpdated
        self.onSearchCompleted = onSearchCompleted
    }

    func replaceRecords(
        _ records: [LocalScanRecord],
        replacing oldRecords: [LocalScanRecord]
    ) {
        self.records = records

        var updatedScanIndexByID: [String: Int] = [:]
        updatedScanIndexByID.reserveCapacity(records.count)
        var updatedScanRecordByID: [String: LocalScanRecord] = [:]
        updatedScanRecordByID.reserveCapacity(records.count)
        var updatedSortPrimitivesByID: [String: ScanSortPrimitive] = [:]
        updatedSortPrimitivesByID.reserveCapacity(records.count)
        var updatedSortPrimitives: [ScanSortPrimitive] = []
        updatedSortPrimitives.reserveCapacity(records.count)

        for (index, scan) in records.enumerated() {
            let primitive = ScanSortPrimitive(
                id: scan.id,
                timestamp: scan.timestamp,
                commonName: scan.commonName
            )
            updatedScanIndexByID[scan.id] = index
            updatedScanRecordByID[scan.id] = scan
            updatedSortPrimitivesByID[scan.id] = primitive
            updatedSortPrimitives.append(primitive)
        }

        scanIndexByID = updatedScanIndexByID
        scanRecordByID = updatedScanRecordByID
        sortPrimitivesByID = updatedSortPrimitivesByID
        allScanSortPrimitives = updatedSortPrimitives
        sortedAllScanIDsCache.removeAll(keepingCapacity: true)
        cacheGeneration &+= 1

        rebuildFilterIndex()
        updateSearchableData(oldRecords: oldRecords)
    }

    func forceReindex(scanID: String) -> Bool {
        guard let scan = record(for: scanID),
              let container = scan.modelContext?.container else {
            return false
        }

        searchTask?.cancel()
        indexingTask?.cancel()
        cacheGeneration &+= 1
        let generation = cacheGeneration

        let updatedPrimitive = ScanSortPrimitive(
            id: scan.id,
            timestamp: scan.timestamp,
            commonName: scan.commonName
        )
        sortPrimitivesByID[scan.id] = updatedPrimitive
        if let index = scanIndexByID[scan.id], allScanSortPrimitives.indices.contains(index) {
            allScanSortPrimitives[index] = updatedPrimitive
        }
        sortedAllScanIDsCache.removeAll(keepingCapacity: true)
        rebuildFilterIndex()

        pendingReindexIDs.insert(scanID)
        if searchIndexSnapshot.count != records.count {
            indexingTask = Task { [weak self] in
                guard let self else { return }
                guard let snapshots = await self.extractRawScanSnapshots(
                    generation: generation
                ) else {
                    return
                }
                guard !Task.isCancelled else { return }

                let worker = Task.detached(priority: .utility) {
                    Self.buildSearchIndexSnapshot(from: snapshots)
                }
                let snapshot = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, self.cacheGeneration == generation else {
                    return
                }

                self.pendingReindexIDs.removeAll()
                self.commitSearchIndexSnapshot(snapshot)
            }
        } else {
            let idsToExtract = Array(pendingReindexIDs)
            indexingTask = Task { [weak self] in
                let databaseActor = SearchDatabaseActor(modelContainer: container)
                let newPayload = await databaseActor.extractSearchablePayloads(
                    from: idsToExtract
                )
                guard !Task.isCancelled, let self else { return }
                guard self.cacheGeneration == generation else { return }

                self.pendingReindexIDs.subtract(idsToExtract)
                self.commitSearchIndexSnapshot(
                    self.searchIndexSnapshot.upserting(newPayload)
                )
            }
        }

        return true
    }

    func refreshExploreShareState() {
        searchTask?.cancel()
        rebuildFilterIndex()
    }

    func performSearch(
        query: String,
        category: String,
        filters: ScanLibraryFilters,
        unavailableExploreMediaScanIDs: Set<String>,
        sortOption: ScanSortOption
    ) {
        searchTask?.cancel()
        #if DEBUG
        debugSearchRequestID &+= 1
        #endif

        let text = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let categoryMatch = category.lowercased()
        let generation = cacheGeneration
        let activeFilterQuery = ScanLibraryFilterQuery(
            filters: filters,
            unavailableExploreMediaScanIDs: unavailableExploreMediaScanIDs
        )
        let searchIndexBuildTask = indexingTask
        let filterIndexBuildTask = filterIndexingTask

        searchTask = Task { [weak self] in
            if !text.isEmpty {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            guard !Task.isCancelled, let self else { return }
            guard self.cacheGeneration == generation else { return }

            if self.records.isEmpty {
                self.completeSearch(with: [], query: text, generation: generation)
                return
            }

            if text.isEmpty,
               categoryMatch == "all",
               !activeFilterQuery.hasAdvancedFilters {
                let sortedIDs = await self.sortedAllScanIDs(
                    for: sortOption,
                    generation: generation
                )
                guard !Task.isCancelled, self.cacheGeneration == generation else {
                    return
                }

                self.completeSearch(
                    with: self.records(for: sortedIDs),
                    query: text,
                    generation: generation
                )
                return
            }

            if text.isEmpty, categoryMatch == "all" {
                await filterIndexBuildTask?.value
            } else {
                await searchIndexBuildTask?.value
                if activeFilterQuery.hasAdvancedFilters {
                    await filterIndexBuildTask?.value
                }
            }
            guard !Task.isCancelled, self.cacheGeneration == generation else {
                return
            }

            let filterIndex = self.filterIndexSnapshot
            if activeFilterQuery.hasAdvancedFilters,
               self.filterIndexSnapshotGeneration != generation {
                return
            }

            let matchingIDs: [String]
            if text.isEmpty, categoryMatch == "all" {
                matchingIDs = filterIndex.allDocumentIDs
            } else {
                let searchIndex = self.searchIndexSnapshot
                if searchIndex.isEmpty {
                    self.completeSearch(with: [], query: text, generation: generation)
                    return
                }

                let filterActor = SearchFilterActor()
                matchingIDs = await filterActor.filter(
                    text: text,
                    searchIndex: searchIndex,
                    catMatch: categoryMatch
                )
            }

            guard !Task.isCancelled, self.cacheGeneration == generation else {
                return
            }

            let sortPrimitivesByID = self.sortPrimitivesByID
            let worker = Task.detached(priority: .userInitiated) { () -> [String] in
                let filteredIDs = filterIndex.matchingIDs(
                    in: matchingIDs,
                    query: activeFilterQuery
                )
                if Task.isCancelled { return [] }

                let subset = filteredIDs.compactMap { sortPrimitivesByID[$0] }
                return ScanLibrarySortPolicy.sort(subset, by: sortOption).map(\.id)
            }
            let sortedIDs = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }

            guard !Task.isCancelled, self.cacheGeneration == generation else {
                return
            }

            self.completeSearch(
                with: self.records(for: sortedIDs),
                query: text,
                generation: generation
            )
        }
    }

    #if DEBUG
    func waitForCurrentSearchCompletionForTesting() async -> ScansLibrarySearchDebugEvent? {
        let expectedRequestID = debugSearchRequestID
        guard let searchTask else { return nil }

        await searchTask.value

        guard debugCompletedSearchRequestID == expectedRequestID else { return nil }
        return debugLastSearchCompletion
    }
    #endif

    private func rebuildFilterIndex() {
        filterIndexingTask?.cancel()
        filterIndexSnapshotGeneration = nil

        let generation = cacheGeneration
        guard !records.isEmpty else {
            commitFilterIndexSnapshot(.empty, generation: generation)
            return
        }

        filterIndexingTask = Task { [weak self] in
            guard let self else { return }
            guard let snapshots = await self.extractRawFilterSnapshots(
                generation: generation
            ) else {
                return
            }
            guard !Task.isCancelled else { return }

            let worker = Task.detached(priority: .utility) {
                ScanLibraryFilterIndexSnapshot(rawSnapshots: snapshots)
            }
            let snapshot = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled, self.cacheGeneration == generation else {
                return
            }

            self.commitFilterIndexSnapshot(snapshot, generation: generation)
        }
    }

    private func updateSearchableData(oldRecords: [LocalScanRecord]) {
        indexingTask?.cancel()

        let oldIDs = Set(oldRecords.map(\.id))
        let newIDs = Set(records.map(\.id))
        pendingReindexIDs.formIntersection(newIDs)

        let addedRecords = records.filter { !oldIDs.contains($0.id) }
        let removedIDs = oldIDs.subtracting(newIDs)
        var workingSnapshot = searchIndexSnapshot

        if !removedIDs.isEmpty {
            workingSnapshot = workingSnapshot.removing(ids: removedIDs)
        }

        guard let firstRecord = records.first,
              let container = firstRecord.modelContext?.container else {
            commitSearchIndexSnapshot(.empty)
            return
        }

        if addedRecords.isEmpty,
           pendingReindexIDs.isEmpty,
           workingSnapshot.count == records.count {
            commitSearchIndexSnapshot(workingSnapshot)
            return
        }

        if workingSnapshot.count != searchIndexSnapshot.count {
            setSearchIndexSnapshot(workingSnapshot, emitCompletion: false)
        }

        let needsFullRebuild = searchIndexSnapshot.isEmpty && !records.isEmpty
        let generation = cacheGeneration

        if needsFullRebuild {
            indexingTask = Task { [weak self] in
                guard let self else { return }
                guard let snapshots = await self.extractRawScanSnapshots(
                    generation: generation
                ) else {
                    return
                }
                guard !Task.isCancelled else { return }

                let worker = Task.detached(priority: .utility) {
                    Self.buildSearchIndexSnapshot(from: snapshots)
                }
                let snapshot = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, self.cacheGeneration == generation else {
                    return
                }

                self.pendingReindexIDs.removeAll()
                self.commitSearchIndexSnapshot(snapshot)
            }
        } else {
            let idsToExtract = Array(
                Set(addedRecords.map(\.id)).union(pendingReindexIDs)
            )
            guard !idsToExtract.isEmpty else { return }

            indexingTask = Task { [weak self] in
                let databaseActor = SearchDatabaseActor(modelContainer: container)
                let processed = await databaseActor.extractSearchablePayloads(
                    from: idsToExtract
                )
                guard !Task.isCancelled, let self else { return }
                guard self.cacheGeneration == generation else { return }

                self.pendingReindexIDs.subtract(idsToExtract)
                self.commitSearchIndexSnapshot(
                    self.searchIndexSnapshot.upserting(processed)
                )
            }
        }
    }

    private func extractRawFilterSnapshots(
        generation: UInt64
    ) async -> [RawScanFilterSnapshot]? {
        let expectedCount = records.count
        var snapshots: [RawScanFilterSnapshot] = []
        snapshots.reserveCapacity(expectedCount)

        var startIndex = 0
        while startIndex < expectedCount {
            guard !Task.isCancelled, cacheGeneration == generation else { return nil }

            let endIndex = min(
                startIndex + Self.rawSnapshotExtractionBatchSize,
                expectedCount
            )
            for index in startIndex..<endIndex {
                let record = records[index]
                snapshots.append(RawScanFilterSnapshot(
                    record: record,
                    isSharedToExplore: sharedPostID(record.id) != nil
                ))
            }

            startIndex = endIndex
            if startIndex < expectedCount {
                await Task.yield()
            }
        }

        guard !Task.isCancelled, cacheGeneration == generation else { return nil }
        return snapshots
    }

    private func extractRawScanSnapshots(
        generation: UInt64
    ) async -> [RawScanSnapshot]? {
        let expectedCount = records.count
        var snapshots: [RawScanSnapshot] = []
        snapshots.reserveCapacity(expectedCount)

        var startIndex = 0
        while startIndex < expectedCount {
            guard !Task.isCancelled, cacheGeneration == generation else { return nil }

            let endIndex = min(
                startIndex + Self.rawSnapshotExtractionBatchSize,
                expectedCount
            )
            for index in startIndex..<endIndex {
                snapshots.append(RawScanSnapshot(record: records[index]))
            }

            startIndex = endIndex
            if startIndex < expectedCount {
                await Task.yield()
            }
        }

        guard !Task.isCancelled, cacheGeneration == generation else { return nil }
        return snapshots
    }

    private func records(for ids: [String]) -> [LocalScanRecord] {
        ids.compactMap { record(for: $0) }
    }

    private func record(for id: String) -> LocalScanRecord? {
        guard let index = scanIndexByID[id], records.indices.contains(index) else {
            return scanRecordByID[id]
        }

        let record = records[index]
        return record.id == id ? record : scanRecordByID[id]
    }

    private func sortedAllScanIDs(
        for sortOption: ScanSortOption,
        generation: UInt64
    ) async -> [String] {
        if let cached = sortedAllScanIDsCache[sortOption.rawValue] {
            return cached
        }

        let primitives = allScanSortPrimitives
        let worker = Task.detached(priority: .userInitiated) {
            ScanLibrarySortPolicy.sort(primitives, by: sortOption).map(\.id)
        }
        let sortedIDs = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }

        if !Task.isCancelled, cacheGeneration == generation {
            sortedAllScanIDsCache[sortOption.rawValue] = sortedIDs
        }
        return sortedIDs
    }

    private func commitSearchIndexSnapshot(_ snapshot: SearchIndexSnapshot) {
        setSearchIndexSnapshot(snapshot, emitCompletion: true)
    }

    private func setSearchIndexSnapshot(
        _ snapshot: SearchIndexSnapshot,
        emitCompletion: Bool
    ) {
        searchIndexSnapshot = snapshot
        if emitCompletion {
            emitIndexingCompletedEvent()
        }
    }

    private func commitFilterIndexSnapshot(
        _ snapshot: ScanLibraryFilterIndexSnapshot,
        generation: UInt64
    ) {
        guard cacheGeneration == generation else { return }
        filterIndexSnapshot = snapshot
        filterIndexSnapshotGeneration = generation
        onFilterIndexUpdated?(snapshot.filterOptions, snapshot.orderedCategoryFilters)
        emitFilterIndexingCompletedEvent()
    }

    private func completeSearch(
        with records: [LocalScanRecord],
        query: String,
        generation: UInt64
    ) {
        guard cacheGeneration == generation, !Task.isCancelled else { return }
        onSearchCompleted?(records, query)
        emitSearchCompletedEvent(query: query, resultCount: records.count)
    }

    private nonisolated static func buildSearchIndexSnapshot(
        from snapshots: [RawScanSnapshot]
    ) -> SearchIndexSnapshot {
        SearchIndexSnapshot(
            searchableScans: SearchDatabaseActor.buildSearchablePayloads(from: snapshots)
        )
    }

    private func emitIndexingCompletedEvent() {
        #if DEBUG
        debugEventHandler?(.indexingCompleted(documentCount: searchIndexSnapshot.count))
        #endif
    }

    private func emitFilterIndexingCompletedEvent() {
        #if DEBUG
        debugEventHandler?(.filterIndexingCompleted(documentCount: filterIndexSnapshot.count))
        #endif
    }

    private func emitSearchCompletedEvent(query: String, resultCount: Int) {
        #if DEBUG
        let event = ScansLibrarySearchDebugEvent.searchCompleted(
            query: query,
            resultCount: resultCount
        )
        debugCompletedSearchRequestID = debugSearchRequestID
        debugLastSearchCompletion = event
        debugEventHandler?(event)
        #endif
    }
}
