import SwiftData
import SwiftUI

/// The fundamental anchor of the Offline-First Architecture. 
/// This completely isolates millions of SQLite computations physically off the UI thread 
/// guaranteeing flawless iOS 120Hz native Scroll geometries.
@ModelActor
actor ProfileDatabaseActor {
    private struct ProfileAnalyticsProjection: AchievementRecordRepresentable, Sendable {
        let id: String
        let speciesId: String
        let scientificName: String
        let userIdentificationOverride: String?
        let confirmedSpeciesId: String?
        let captureDate: Date?
        let taxonomyKingdom: String?
        let taxonomyClass: String?
        let ecologyType: String
        let weatherTemperatureF: Double?
        let gpsElevation: Double?
        let timestamp: Date
        let isBiological: Bool
        let isInvasive: Bool
        let iucnRedListStatus: String?
        let hazardType: String
        let confidenceScore: Double?
    }

    private struct ProfileAchievementDetailProjection: AchievementRecordRepresentable, Sendable {
        let id: String
        let speciesId: String
        let scientificName: String
        let userIdentificationOverride: String?
        let confirmedSpeciesId: String?
        let timestamp: Date
        let captureDate: Date?
        let taxonomyKingdom: String?
        let taxonomyClass: String?
        let ecologyType: String
        let weatherTemperatureF: Double?
        let gpsElevation: Double?
        let isBiological: Bool
        let isInvasive: Bool
        let iucnRedListStatus: String?
        let hazardType: String
        let confidenceScore: Double?
        let commonName: String?
        let locationName: String?
        let imagePath: String?
        let fallbackImageUrl: String?
        let audioPath: String?
        let placeholderStyle: ScanThumbnailPlaceholderStyle
    }

    private struct ProfileProjectionFingerprint: Equatable {
        let recordCount: Int
        let latestScanId: String?
        let latestTimestamp: Date?

        static let empty = ProfileProjectionFingerprint(
            recordCount: 0,
            latestScanId: nil,
            latestTimestamp: nil
        )

        init(recordCount: Int, latestScanId: String?, latestTimestamp: Date?) {
            self.recordCount = recordCount
            self.latestScanId = latestScanId
            self.latestTimestamp = latestTimestamp
        }

        init(analyticsRecords records: [ProfileAnalyticsProjection]) {
            self.init(
                recordCount: records.count,
                latestScanId: records.first?.id,
                latestTimestamp: records.first?.timestamp
            )
        }

        init(detailRecords records: [ProfileAchievementDetailProjection]) {
            self.init(
                recordCount: records.count,
                latestScanId: records.first?.id,
                latestTimestamp: records.first?.timestamp
            )
        }
    }

    private struct ProfileStatsProjection {
        let fingerprint: ProfileProjectionFingerprint
        let records: [ProfileAnalyticsProjection]
        let timestamps: [Date]
        let speciesCount: Int

        init(records: [ProfileAnalyticsProjection]) {
            var timestamps: [Date] = []
            timestamps.reserveCapacity(records.count)

            var uniqueSpecies = Set<String>()
            uniqueSpecies.reserveCapacity(records.count)

            for record in records {
                timestamps.append(record.timestamp)
                uniqueSpecies.insert(record.scientificName)
            }

            self.fingerprint = ProfileProjectionFingerprint(analyticsRecords: records)
            self.records = records
            self.timestamps = timestamps
            self.speciesCount = uniqueSpecies.count
        }
    }

    private var cachedStatsProjection: ProfileStatsProjection?
    private var cachedAwardPayloads: [AwardPayload]?
    private var cachedAchievementDetailProjection: (
        fingerprint: ProfileProjectionFingerprint,
        records: [ProfileAchievementDetailProjection]
    )?

    private func currentProjectionFingerprint() -> ProfileProjectionFingerprint {
        let count = (try? modelContext.fetchCount(FetchDescriptor<LocalScanRecord>())) ?? 0
        guard count > 0 else { return .empty }

        var latestDescriptor = FetchDescriptor<LocalScanRecord>(
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        latestDescriptor.fetchLimit = 1
        latestDescriptor.propertiesToFetch = [\.id, \.timestamp]

        let latestRecord = ((try? modelContext.fetch(latestDescriptor)) ?? []).first
        return ProfileProjectionFingerprint(
            recordCount: count,
            latestScanId: latestRecord?.id,
            latestTimestamp: latestRecord?.timestamp
        )
    }

    private func loadStatsProjection() -> ProfileStatsProjection {
        if let cachedStatsProjection,
           currentProjectionFingerprint() == cachedStatsProjection.fingerprint {
            return cachedStatsProjection
        }

        let projection = ProfileStatsProjection(records: fetchAnalyticsProjection())
        cachedStatsProjection = projection
        cachedAwardPayloads = nil
        return projection
    }

    private func loadAchievementDetailProjection() -> [ProfileAchievementDetailProjection] {
        if let cachedAchievementDetailProjection,
           currentProjectionFingerprint() == cachedAchievementDetailProjection.fingerprint {
            return cachedAchievementDetailProjection.records
        }

        let records = fetchAchievementDetailProjection()
        cachedAchievementDetailProjection = (
            fingerprint: ProfileProjectionFingerprint(detailRecords: records),
            records: records
        )
        return records
    }

    private func awardPayloads(for projection: ProfileStatsProjection) -> [AwardPayload] {
        if let cachedAwardPayloads {
            return cachedAwardPayloads
        }

        let awards = AchievementsCalculator.calculate(from: projection.records)
        cachedAwardPayloads = awards
        return awards
    }

    private func fetchAnalyticsProjection() -> [ProfileAnalyticsProjection] {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.propertiesToFetch = [
            \.id, \.speciesId, \.scientificName, \.userIdentificationOverride, \.confirmedSpeciesId, \.captureDate,
            \.taxonomyKingdom, \.taxonomyClass, \.ecologyType, \.weatherTemperatureF,
            \.gpsElevation, \.timestamp, \.isBiological, \.isInvasive, \.iucnRedListStatus, \.hazardType,
            \.confidenceScore
        ]

        guard let records = try? modelContext.fetch(descriptor) else { return [] }
        return records.map {
            ProfileAnalyticsProjection(
                id: $0.id,
                speciesId: $0.speciesId,
                scientificName: $0.scientificName,
                userIdentificationOverride: $0.userIdentificationOverride,
                confirmedSpeciesId: $0.confirmedSpeciesId,
                captureDate: $0.captureDate,
                taxonomyKingdom: $0.taxonomyKingdom,
                taxonomyClass: $0.taxonomyClass,
                ecologyType: $0.ecologyType,
                weatherTemperatureF: $0.weatherTemperatureF,
                gpsElevation: $0.gpsElevation,
                timestamp: $0.timestamp,
                isBiological: $0.isBiological,
                isInvasive: $0.isInvasive,
                iucnRedListStatus: $0.iucnRedListStatus,
                hazardType: $0.hazardType,
                confidenceScore: $0.confidenceScore
            )
        }
    }

    private func fetchAchievementDetailProjection() -> [ProfileAchievementDetailProjection] {
        var descriptor = FetchDescriptor<LocalScanRecord>(
            sortBy: [
                SortDescriptor(\.timestamp, order: .reverse),
                SortDescriptor(\.id, order: .reverse)
            ]
        )
        descriptor.propertiesToFetch = [
            \.id, \.speciesId, \.scientificName, \.userIdentificationOverride, \.confirmedSpeciesId,
            \.timestamp, \.captureDate, \.taxonomyKingdom, \.taxonomyClass, \.ecologyType, \.weatherTemperatureF,
            \.gpsElevation, \.isInvasive, \.iucnRedListStatus, \.hazardType, \.confidenceScore,
            \.commonName, \.locationName, \.coverImagePath, \.capturedMediaJSON, \.referenceImageUrl,
            \.isBiological, \.isLocallyArchived
        ]

        guard let records = try? modelContext.fetch(descriptor) else { return [] }
        return records.map { record in
            let thumbnail = record.scanThumbnailPresentation
            return ProfileAchievementDetailProjection(
                id: record.id,
                speciesId: record.speciesId,
                scientificName: record.scientificName,
                userIdentificationOverride: record.userIdentificationOverride,
                confirmedSpeciesId: record.confirmedSpeciesId,
                timestamp: record.timestamp,
                captureDate: record.captureDate,
                taxonomyKingdom: record.taxonomyKingdom,
                taxonomyClass: record.taxonomyClass,
                ecologyType: record.ecologyType,
                weatherTemperatureF: record.weatherTemperatureF,
                gpsElevation: record.gpsElevation,
                isBiological: record.isBiological,
                isInvasive: record.isInvasive,
                iucnRedListStatus: record.iucnRedListStatus,
                hazardType: record.hazardType,
                confidenceScore: record.confidenceScore,
                commonName: record.commonName,
                locationName: record.locationName,
                imagePath: thumbnail.imagePath,
                fallbackImageUrl: thumbnail.fallbackImageUrl,
                audioPath: thumbnail.audioPath,
                placeholderStyle: thumbnail.placeholderStyle
            )
        }
    }

    private func calculateStreak(from timestamps: [Date], now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let sortedDates = Array(Set(timestamps.map { calendar.startOfDay(for: $0) })).sorted(by: >)

        var streak = 0
        var expectedDate = today
        if !sortedDates.contains(today) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), sortedDates.contains(yesterday) {
                expectedDate = yesterday
            } else {
                return 0
            }
        }

        for date in sortedDates {
            if calendar.isDate(date, inSameDayAs: expectedDate) {
                streak += 1
                expectedDate = calendar.date(byAdding: .day, value: -1, to: expectedDate) ?? expectedDate
            } else {
                break
            }
        }

        return streak
    }

    private func buildHeatmapData(from timestamps: [Date], now: Date = Date()) -> ProfileHeatmapData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var counts: [Date: Int] = [:]

        for timestamp in timestamps {
            counts[calendar.startOfDay(for: timestamp), default: 0] += 1
        }

        let currentYear = calendar.component(.year, from: today)
        let weekday = calendar.component(.weekday, from: today)
        let daysToSaturday = 7 - weekday
        guard let endOfWeek = calendar.date(byAdding: .day, value: daysToSaturday, to: today) else {
            let total = counts.values.reduce(0, +)
            return ProfileHeatmapData(totalCaptures: total, currentMonthCaptures: 0, yearString: "\(currentYear)", weeks: [])
        }

        let daysInWeek = 7
        let weeksInYear = 52
        let totalDays = weeksInYear * daysInWeek
        guard let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: endOfWeek) else {
            let total = counts.values.reduce(0, +)
            return ProfileHeatmapData(totalCaptures: total, currentMonthCaptures: 0, yearString: "\(currentYear)", weeks: [])
        }

        var weeks: [HeatmapWeek] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        var currentMonth = -1
        var totalInHeatmap = 0
        var currentMonthCaptures = 0
        var currentDate = startDate

        for _ in 0..<weeksInYear {
            var days: [HeatmapDay] = []
            var monthLabel: String?

            for dayIndex in 0..<daysInWeek {
                if dayIndex == 0 {
                    let month = calendar.component(.month, from: currentDate)
                    if month != currentMonth {
                        currentMonth = month
                        monthLabel = formatter.string(from: currentDate)
                    }
                }

                let count: Int
                if currentDate > today {
                    count = -1
                } else {
                    count = counts[currentDate] ?? 0
                    totalInHeatmap += count
                    if calendar.isDate(currentDate, equalTo: now, toGranularity: .month) {
                        currentMonthCaptures += count
                    }
                }

                days.append(HeatmapDay(count: count, date: currentDate))
                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
            }

            weeks.append(HeatmapWeek(days: days, monthLabel: monthLabel))
        }

        return ProfileHeatmapData(
            totalCaptures: totalInHeatmap,
            currentMonthCaptures: currentMonthCaptures,
            yearString: "\(currentYear)",
            weeks: weeks
        )
    }

    func invalidateCachedProfileProjections() {
        cachedStatsProjection = nil
        cachedAwardPayloads = nil
        cachedAchievementDetailProjection = nil
    }

    func calculateProfileStats() -> (speciesCount: Int, streak: Int) {
        let projection = loadStatsProjection()
        let streak = calculateStreak(from: projection.timestamps)
        return (projection.speciesCount, streak)
    }
    
    func calculateAll() -> ProfileAllStatsPayload {
        let projection = loadStatsProjection()
        let awards = awardPayloads(for: projection)

        let now = Date()
        let streak = calculateStreak(from: projection.timestamps, now: now)
        let heatmap = buildHeatmapData(from: projection.timestamps, now: now)

        return ProfileAllStatsPayload(
            speciesCount: projection.speciesCount,
            streak: streak,
            heatmap: heatmap,
            awards: awards
        )
    }

    func calculateHeatmapData() -> ProfileHeatmapData {
        let projection = loadStatsProjection()
        return buildHeatmapData(from: projection.timestamps)
    }

    func calculateAwardsProjection() -> [AwardPayload] {
        let projection = loadStatsProjection()
        return awardPayloads(for: projection)
    }

    func calculateAchievementDetail(for type: AchievementType) -> AchievementDetailPayload? {
        AchievementsCalculator.detail(for: type, from: loadAchievementDetailProjection())
    }
    
}

// MARK: - Native Thread-Safe Architectures
// Explicit `Sendable` conformity fundamentally guarantees Apple's compiler instantly halts
// compilation if accidental memory-race conditions attempt to cross Thread boundaries.
struct HeatmapDay: Sendable, Identifiable {
    let id = UUID()
    let count: Int
    let date: Date
}

struct HeatmapWeek: Sendable, Identifiable {
    let id = UUID()
    let days: [HeatmapDay]
    let monthLabel: String?
}

struct ProfileHeatmapData: Sendable {
    let totalCaptures: Int
    let currentMonthCaptures: Int
    let yearString: String
    let weeks: [HeatmapWeek]
}

struct ProfileAllStatsPayload: Sendable {
    let speciesCount: Int
    let streak: Int
    let heatmap: ProfileHeatmapData
    let awards: [AwardPayload]
}

struct UserStats: View {
    let speciesCount: Int
    let streak: Int
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Species discovered", value: "\(speciesCount)", imageName: "leaf", color: .green)
            StatCard(title: "Current streak", value: "\(streak) day\(streak == 1 ? "" : "s")", imageName: "fire", color: .orange)
        }
    }
}
