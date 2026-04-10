import XCTest
import SwiftData
@testable import Merian

@MainActor
final class ProfileDatabaseActorTests: XCTestCase {
    
    private var container: ModelContainer!
    
    override func setUpWithError() throws {
        // Enforce pure volatile memory architecture specifically so Simulator database 
        // disk I/O logic never mutates actual User-facing state!
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema([LocalScanRecord.self])
        container = try ModelContainer(for: schema, configurations: [configuration])
    }
    
    override func tearDownWithError() throws {
        container = nil
    }
    
    // MARK: - Generator
    
    /// Safely mounts ephemeral SwiftData structures by mapping arrays of timezone-adjusted day offsets natively.
    /// Example: `0` injects a scan at exactly `12:00 PM` today. `-1` injects a scan exactly yesterday.
    private func processScans(offsets: [Int]) async throws -> ProfileDatabaseActor {
        let context = container.mainContext
        let calendar = Calendar.current
        let noonToday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        
        for offset in offsets {
            let targetDate = calendar.date(byAdding: .day, value: offset, to: noonToday)!
            let scan = LocalScanRecord(
                speciesId: UUID().uuidString,
                scientificName: "Test Species \(offset)_\(UUID().uuidString.prefix(4))",
                commonName: "Test",
                timestamp: targetDate,
                ecologyType: "unknown"
            )
            context.insert(scan)
        }
        
        try context.save()
        return ProfileDatabaseActor(modelContainer: container)
    }
    
    // MARK: - Validation Suites
    
    func testStreakActiveGracePeriod() async throws {
        // Simulate missing today (0), but having scanned continuously for 3 preceding days.
        let actor = try await processScans(offsets: [-1, -2, -3])
        let payload: ProfileAllStatsPayload = await actor.calculateAll()
        
        XCTAssertEqual(payload.streak, 3, "Grace period constraint breached! Missing today natively assumes a live streak anchor tied securely to yesterday mathematically.")
    }
    
    func testStreakBroken() async throws {
        // Simulate missing today (0) AND yesterday (-1)
        let actor = try await processScans(offsets: [-2, -3, -4])
        let payload: ProfileAllStatsPayload = await actor.calculateAll()
        
        XCTAssertEqual(payload.streak, 0, "Missing both boundary bounds simultaneously must absolutely zero the streak completely!")
    }
    
    func testStreakRedundancy() async throws {
        // Simulating multiple scans fired natively on identically same calendar days.
        let actor = try await processScans(offsets: [-1, -1, -2, -3])
        let payload: ProfileAllStatsPayload = await actor.calculateAll()
        
        XCTAssertEqual(payload.streak, 3, "Streak logic deduplication compromised! Array maps must strictly uniquely fold identically anchored offset variables!")
    }
    
    func testHeatmapMatrixBounds() async throws {
        var massiveDistribution: [Int] = []
        // Massively bombards the footprint bounds logic strictly inside the 52-week geometry window!
        for _ in 0..<500 { massiveDistribution.append(Int.random(in: -360...0)) }
        
        let actor = try await processScans(offsets: massiveDistribution)
        let heatmap = await actor.calculateHeatmapData()
        
        // Assert the matrix mathematically respects constraints despite chaotic time bounds logic inside the nested algorithms
        XCTAssertEqual(heatmap.weeks.count, 52, "Geometric grid fundamentally crashed generating 52 layout boundaries!")
        XCTAssertEqual(heatmap.totalCaptures, 500, "Math engine failed summing native database bindings correctly.")
        
        // Assert precisely 7 independent vertical structures generated securely inside columns
        for week in heatmap.weeks {
            XCTAssertEqual(week.days.count, 7, "Geometry structurally failed plotting exactly 7 strict days vertically inside bounds!")
        }
    }
}
