import Foundation
import Testing

@Suite("Environment context architecture")
struct EnvironmentContextArchitectureTests {
    @Test("Facade and hardware effects have focused owners")
    func declarationsHaveFocusedOwners() throws {
        let manager = try source(Self.managerPath)
        let models = try source(Self.modelsPath)
        let policy = try source(Self.policyPath)
        let locationController = try source(Self.locationControllerPath)
        let geocodingService = try source(Self.geocodingServicePath)
        let weatherService = try source(Self.weatherServicePath)

        for relocatedToken in [
            "CLLocationManagerDelegate",
            "CLLocationManager()",
            "CLGeocoder",
            "WeatherService.shared",
            "CheckedContinuation",
            "activeGeocodeTasks",
            "timeoutTask"
        ] {
            #expect(!manager.contains(relocatedToken))
        }

        #expect(models.contains("struct EnvironmentContext"))
        #expect(policy.contains("enum EnvironmentLocationPolicy"))
        #expect(
            locationController.contains(
                "final class EnvironmentLocationController"
            )
        )
        #expect(locationController.contains("timeoutGeneration"))
        #expect(
            geocodingService.contains(
                "final class EnvironmentGeocodingService"
            )
        )
        #expect(geocodingService.contains("activeRequests"))
        #expect(weatherService.contains("WeatherService.shared"))
    }

    @Test("Deterministic layers remain free of live services and task state")
    func deterministicLayersRemainFocused() throws {
        for path in [Self.modelsPath, Self.policyPath] {
            let contents = try source(path)
            for forbidden in [
                "import MapKit",
                "import Observation",
                "import WeatherKit",
                ".shared",
                "Task {",
                "CLGeocoder",
                "CLLocationManager()",
                "MerianNetworkClient",
                "SupabaseManager"
            ] {
                #expect(!contents.contains(forbidden))
            }
        }

        let manager = try source(Self.managerPath)
        #expect(!manager.contains("import MapKit"))
        #expect(!manager.contains("import WeatherKit"))

        let locationController = try source(Self.locationControllerPath)
        #expect(!locationController.contains("import WeatherKit"))
        #expect(!locationController.contains("CLGeocoder"))

        let geocodingService = try source(Self.geocodingServicePath)
        #expect(!geocodingService.contains("import WeatherKit"))
        #expect(!geocodingService.contains("CLLocationManager"))
    }

    @Test("Stable facade methods remain available")
    func facadeCompatibilitySurfaceRemainsStable() throws {
        let manager = try source(Self.managerPath)
        for declaration in [
            "func validatePermissions()",
            "func requestLocationAuthorizationIfNeeded()",
            "func requestCurrentLocation()",
            "func currentAuthorizedRegionIdentifier()",
            "func currentAuthorizedLocationName()",
            "func startLiveLocationTracking()",
            "func stopLiveLocationTracking()",
            "func fetchDeferredContext(",
            "func fetchHistoricalContext("
        ] {
            #expect(manager.contains(declaration))
        }
    }

    @Test("Every environment-context production owner remains focused")
    func ownersRemainBelowLineCeilings() throws {
        #expect(lineCount(try source(Self.managerPath)) <= 250)
        #expect(lineCount(try source(Self.modelsPath)) <= 75)
        #expect(lineCount(try source(Self.policyPath)) <= 100)
        #expect(lineCount(try source(Self.locationControllerPath)) <= 375)
        #expect(lineCount(try source(Self.geocodingServicePath)) <= 175)
        #expect(lineCount(try source(Self.weatherServicePath)) <= 100)
    }

    @Test("The aggregate model and test files are retired")
    func aggregateFilesAreRetired() throws {
        let root = try repositoryRoot()
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(Self.oldModelPath).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: root.appendingPathComponent(Self.oldTestsPath).path
            )
        )
    }

    private func source(_ path: String) throws -> String {
        let file = try repositoryRoot().appendingPathComponent(path)
        return try String(contentsOf: file, encoding: .utf8)
    }

    private func lineCount(_ source: String) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static let managerPath =
        "apps/ios/Merian/Core/Hardware/EnvironmentContextManager.swift"
    private static let modelsPath =
        "apps/ios/Merian/Core/Hardware/EnvironmentContext/Models/" +
        "EnvironmentContextModels.swift"
    private static let policyPath =
        "apps/ios/Merian/Core/Hardware/EnvironmentContext/Policies/" +
        "EnvironmentLocationPolicy.swift"
    private static let locationControllerPath =
        "apps/ios/Merian/Core/Hardware/EnvironmentContext/Services/" +
        "EnvironmentLocationController.swift"
    private static let geocodingServicePath =
        "apps/ios/Merian/Core/Hardware/EnvironmentContext/Services/" +
        "EnvironmentGeocodingService.swift"
    private static let weatherServicePath =
        "apps/ios/Merian/Core/Hardware/EnvironmentContext/Services/" +
        "EnvironmentWeatherService.swift"
    private static let oldModelPath =
        "apps/ios/Merian/Core/Hardware/EnvironmentContext.swift"
    private static let oldTestsPath =
        "apps/ios/MerianTests/Core/Hardware/EnvironmentContextManagerTests.swift"
}
