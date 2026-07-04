import Testing
import Foundation
@testable import Merian

struct MerianConfigTests {
    
    @Test func testInferenceImageMaxSizeResolvesTargetDimensions() {
        // Act & Assert
        let proSize = MerianConfig.inferenceImageMaxSize(isProActive: true)
        let freeSize = MerianConfig.inferenceImageMaxSize(isProActive: false)
        
        #expect(proSize == 1024.0, "Pro subscriptions must target 1024px maximum long-edge dimension")
        #expect(freeSize == 768.0, "Free subscriptions must cap at 768px maximum long-edge dimension to save tokens")
    }
    
    @Test func testConfidenceBandsResolveByTier() {
        // Act
        let proBands = MerianConfig.confidenceBands(forInferenceTier: "pro")
        let flashBands = MerianConfig.confidenceBands(forInferenceTier: "flash")
        
        // Assert Pro uses a more relaxed boundary because it's highly calibrated
        #expect(proBands.strong == 0.85)
        #expect(proBands.possible == 0.65)
        #expect(proBands.diagnosticTrigger == 0.99)
        
        // Assert Flash uses a strict boundary because it's fast and slightly overconfident
        #expect(flashBands.strong == 0.95)
        #expect(flashBands.possible == 0.75)
        #expect(flashBands.diagnosticTrigger == 0.99)
    }
    
    @Test func testMissingTierFallsBackToFlashBandsGracefully() {
        // Act
        let standardBands = MerianConfig.confidenceBands(forInferenceTier: nil)
        
        // Assert
        #expect(standardBands.strong == 0.95) // Maps to Flash defaults safely
    }
}

@Suite("Explore Error Formatter Tests")
struct ExploreErrorFormatterTests {

    @Test func duplicateScanPrimaryKeyErrorsUseShareRecoveryCopy() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 409,
            message: "duplicate key value violates unique constraint \"scans_pkey\""
        ))

        #expect(message == "This scan is already saved. Try sharing again.")
    }

    @Test func jsonWrappedDuplicateScanErrorsAreSanitized() {
        let rawMessage = #"{"error":"duplicate key value violates unique constraint \"scans_pkey\""}"#

        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 409,
            message: rawMessage
        ))

        #expect(message == "This scan is already saved. Try sharing again.")
    }

    @Test func friendlyApiErrorsPassThrough() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 409,
            message: "Only biological scans can be shared to Explore."
        ))

        #expect(message == "Only biological scans can be shared to Explore.")
    }

    @Test func technicalPersistenceErrorsUseGenericPersistenceCopy() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 400,
            message: "null value in column \"species_id\" violates not-null constraint"
        ))

        #expect(message == "We couldn’t finish that. Please try again.")
    }

    @Test func emptyHttpErrorsUseGenericCopy() {
        let message = ExploreErrorFormatter.message(for: MerianError.httpError(
            statusCode: 400,
            message: "   "
        ))

        #expect(message == "Something went wrong. Please try again.")
    }

    @Test func titledMessagesPreserveSanitizedBody() {
        let message = ExploreErrorFormatter.titledMessage(
            "Couldn’t share to Explore",
            for: MerianError.httpError(
                statusCode: 409,
                message: "duplicate key value violates unique constraint \"scans_pkey\""
            )
        )

        #expect(message == "Couldn’t share to Explore\nThis scan is already saved. Try sharing again.")
    }
}

@Suite("Merian Environment Tests")
struct MerianEnvironmentTests {

    @Test func missingInfoDictionaryFallsBackWithoutCrashing() {
        let configuration = MerianEnvironment.load(infoDictionary: nil)

        #expect(configuration.supabaseUrl == MerianEnvironment.fallbackSupabaseURL)
        #expect(configuration.hasSupabaseConfiguration == false)
        #expect(configuration.issues.contains(.missingInfoDictionary))
        #expect(configuration.issues.contains(.missingValue("SUPABASE_URL")))
        #expect(configuration.issues.contains(.missingValue("SUPABASE_ANON_KEY")))
    }

    @Test func invalidSupabaseURLFallsBackAndReportsDiagnostic() {
        let configuration = MerianEnvironment.load(infoDictionary: [
            "SUPABASE_URL": "not a valid url",
            "SUPABASE_ANON_KEY": "anon-key",
            "REVENUECAT_API_KEY": "revenuecat-key",
            "POSTHOG_API_KEY": "posthog-key",
            "TELEMETRY_APP_ID": "telemetry-id"
        ])

        #expect(configuration.supabaseUrl == MerianEnvironment.fallbackSupabaseURL)
        #expect(configuration.supabaseAnonKey == "anon-key")
        #expect(configuration.hasSupabaseConfiguration == false)
        #expect(configuration.issues.contains(.invalidSupabaseURL("not a valid url")))
    }

    @Test func validConfigurationTrimsValuesAndReportsNoIssues() {
        let configuration = MerianEnvironment.load(infoDictionary: [
            "SUPABASE_URL": " https://project.supabase.co ",
            "SUPABASE_ANON_KEY": " anon-key ",
            "REVENUECAT_API_KEY": " revenuecat-key ",
            "POSTHOG_API_KEY": " posthog-key ",
            "TELEMETRY_APP_ID": " telemetry-id "
        ])

        #expect(configuration.supabaseUrl == "https://project.supabase.co")
        #expect(configuration.supabaseAnonKey == "anon-key")
        #expect(configuration.revenueCatApiKey == "revenuecat-key")
        #expect(configuration.postHogApiKey == "posthog-key")
        #expect(configuration.telemetryAppID == "telemetry-id")
        #expect(configuration.hasSupabaseConfiguration)
        #expect(configuration.issues.isEmpty)
    }
}
