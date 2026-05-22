import Foundation
import Observation
import SwiftData

struct SpeciesObservationLocalStats: Equatable {
    let seasonality: [SpeciesObservationMonthCount]
    let history: [SpeciesObservationHistoryCount]
    let lifeStage: [SpeciesObservationCategorySeries]
    let totalObservations: Int
    let lastObservationDate: Date?

    static func empty(now: Date = Date()) -> SpeciesObservationLocalStats {
        SpeciesObservationLocalStats(
            seasonality: SpeciesObservationStatsViewModel.emptyMonthCounts(),
            history: SpeciesObservationStatsViewModel.emptyHistoryCounts(now: now),
            lifeStage: [],
            totalObservations: 0,
            lastObservationDate: nil
        )
    }
}

@MainActor
@Observable
final class SpeciesObservationStatsViewModel {
    private(set) var isLoading = false
    private(set) var localStats = SpeciesObservationLocalStats.empty()
    private(set) var publicStats: SpeciesObservationStatsEntry?
    private(set) var publicErrorMessage: String?
    private var activeLoadId: UUID?

    var hasAnyData: Bool {
        localStats.totalObservations > 0 ||
        (publicStats?.totalObservations ?? 0) > 0 ||
        publicStats?.seasonality.contains(where: \.hasObservations) == true ||
        publicStats?.history.contains(where: \.hasObservations) == true ||
        publicStats?.lifeStage.contains(where: { series in
            series.values.contains(where: \.hasObservations)
        }) == true
    }

    func load(
        speciesId: String?,
        scientificName: String,
        modelContext: ModelContext,
        now: Date = Date()
    ) async {
        let normalizedName = Self.normalizedScientificName(scientificName)
        guard !normalizedName.isEmpty else {
            localStats = .empty(now: now)
            publicStats = nil
            publicErrorMessage = nil
            return
        }

        let loadId = UUID()
        activeLoadId = loadId
        isLoading = true
        defer {
            if activeLoadId == loadId {
                isLoading = false
            }
        }
        publicErrorMessage = nil
        let local = Self.fetchLocalStats(
            scientificName: normalizedName,
            speciesId: speciesId,
            modelContext: modelContext,
            now: now
        )
        if activeLoadId == loadId {
            localStats = local
        }

        do {
            let stats = try await MerianNetworkClient.shared.getSpeciesObservationStats(
                speciesId: speciesId,
                scientificName: normalizedName
            )
            if activeLoadId == loadId {
                publicStats = stats
            }
        } catch is CancellationError {
            // Task was cancelled, ignore.
            return
        } catch {
            if activeLoadId == loadId {
                publicStats = nil
                publicErrorMessage = error.localizedDescription
            }
        }
    }

    static func fetchLocalStats(
        scientificName: String,
        speciesId: String?,
        modelContext: ModelContext,
        now: Date = Date()
    ) -> SpeciesObservationLocalStats {
        let targetName = normalizedScientificName(scientificName).lowercased()
        let targetSpeciesId = normalizedSpeciesId(speciesId)
        let calendar = Calendar(identifier: .gregorian)
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { record in
                record.isBiological == true
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        let records = (try? modelContext.fetch(descriptor)) ?? []
        let matchingRecords = records.filter { record in
            guard recordMatches(record, targetName: targetName, targetSpeciesId: targetSpeciesId) else {
                return false
            }
            return true
        }

        var monthCounts = Dictionary(uniqueKeysWithValues: (1...12).map { ($0, 0) })
        var historyCounts: [String: Int] = [:]
        var lifeStageMonthCounts: [String: [Int: Int]] = [:]
        var lifeStageLabels: [String: String] = [:]
        var lastObservationDate: Date?

        let historyStart = calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: calendar.component(.year, from: now) - 6,
                month: 1,
                day: 1
            )
        ) ?? now
        let currentMonthStart = calendar.date(
            from: DateComponents(
                calendar: calendar,
                year: calendar.component(.year, from: now),
                month: calendar.component(.month, from: now),
                day: 1
            )
        ) ?? now

        for record in matchingRecords {
            let observationDate = record.captureDate ?? record.timestamp
            let month = calendar.component(.month, from: observationDate)
            monthCounts[month, default: 0] += 1

            if lastObservationDate == nil || observationDate > lastObservationDate! {
                lastObservationDate = observationDate
            }

            let observationMonthStart = calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    year: calendar.component(.year, from: observationDate),
                    month: calendar.component(.month, from: observationDate),
                    day: 1
                )
            ) ?? observationDate
            if observationMonthStart >= historyStart && observationMonthStart <= currentMonthStart {
                let key = historyKey(for: observationDate, calendar: calendar)
                historyCounts[key, default: 0] += 1
            }

            if let stage = normalizedLifeStage(record.lifeStage) {
                lifeStageLabels[stage.key] = stage.label
                lifeStageMonthCounts[stage.key, default: Dictionary(uniqueKeysWithValues: (1...12).map { ($0, 0) })][month, default: 0] += 1
            }
        }

        let seasonality = (1...12).map { month in
            SpeciesObservationMonthCount(month: month, count: monthCounts[month, default: 0])
        }
        let history = historyBuckets(now: now, calendar: calendar).map { bucket in
            SpeciesObservationHistoryCount(
                year: bucket.year,
                month: bucket.month,
                count: historyCounts[bucket.key, default: 0]
            )
        }
        let lifeStage = lifeStageMonthCounts.keys.sorted().map { key in
            SpeciesObservationCategorySeries(
                key: key,
                label: lifeStageLabels[key] ?? key,
                values: (1...12).map { month in
                    SpeciesObservationMonthCount(
                        month: month,
                        count: lifeStageMonthCounts[key]?[month, default: 0] ?? 0
                    )
                }
            )
        }
        return SpeciesObservationLocalStats(
            seasonality: seasonality,
            history: history,
            lifeStage: lifeStage,
            totalObservations: matchingRecords.count,
            lastObservationDate: lastObservationDate
        )
    }

    nonisolated static func emptyMonthCounts() -> [SpeciesObservationMonthCount] {
        (1...12).map { SpeciesObservationMonthCount(month: $0, count: 0) }
    }

    nonisolated static func emptyHistoryCounts(now: Date = Date()) -> [SpeciesObservationHistoryCount] {
        historyBuckets(now: now, calendar: Calendar(identifier: .gregorian)).map {
            SpeciesObservationHistoryCount(year: $0.year, month: $0.month, count: 0)
        }
    }

    private static func recordMatches(
        _ record: LocalScanRecord,
        targetName: String,
        targetSpeciesId: String?
    ) -> Bool {
        if let targetSpeciesId {
            let recordIds = [
                normalizedSpeciesId(record.confirmedSpeciesId),
                normalizedSpeciesId(record.speciesId)
            ]
            if recordIds.contains(targetSpeciesId) {
                return true
            }
        }

        let effectiveName = normalizedScientificName(
            record.userIdentificationOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ??
            record.scientificName
        )
        return effectiveName.lowercased() == targetName
    }

    private static func normalizedScientificName(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizedSpeciesId(_ value: String?) -> String? {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .nilIfEmpty
    }

    private static func normalizedLifeStage(_ value: String?) -> (key: String, label: String)? {
        normalizedCategory(value, excluding: ["unknown", "not_applicable", "not applicable", "n/a", "none"])
    }

    private static func normalizedCategory(_ value: String?, excluding excluded: Set<String>) -> (key: String, label: String)? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }

        let lowered = trimmed.lowercased()
        guard !excluded.contains(lowered) else { return nil }

        let key = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        guard !key.isEmpty else { return nil }

        let label = trimmed
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")
        return (key, label)
    }

    nonisolated private static func historyBuckets(
        now: Date,
        calendar: Calendar
    ) -> [SpeciesObservationHistoryBucket] {
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        var buckets: [SpeciesObservationHistoryBucket] = []

        for year in (currentYear - 6)...currentYear {
            let endMonth = year == currentYear ? currentMonth : 12
            for month in 1...endMonth {
                let key = "\(year)-\(String(format: "%02d", month))"
                buckets.append(SpeciesObservationHistoryBucket(year: year, month: month, key: key))
            }
        }

        return buckets
    }

    private static func historyKey(for date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return "\(year)-\(String(format: "%02d", month))"
    }
}

private struct SpeciesObservationHistoryBucket {
    let year: Int
    let month: Int
    let key: String
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
