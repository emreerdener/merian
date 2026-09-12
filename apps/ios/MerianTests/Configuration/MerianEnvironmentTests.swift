import Foundation
@testable import Merian
import Testing

@Suite("Merian Environment Tests")
struct MerianEnvironmentTests {
    @Test func missingInfoDictionaryFallsBackWithoutCrashing() {
        let configuration = MerianEnvironment.load(infoDictionary: nil)

        #expect(configuration.supabaseUrl == MerianEnvironment.fallbackSupabaseURL)
        #expect(!configuration.hasSupabaseConfiguration)
        #expect(configuration.issues.contains(.missingInfoDictionary))
        #expect(configuration.issues.contains(.missingValue("SUPABASE_URL")))
        #expect(configuration.issues.contains(.missingValue("SUPABASE_ANON_KEY")))
    }

    @Test func invalidSupabaseURLFallsBackAndReportsDiagnostic() {
        let configuration = MerianEnvironment.load(infoDictionary: [
            "SUPABASE_URL": "not a valid url",
            "SUPABASE_ANON_KEY": "anon-key",
            "REVENUECAT_API_KEY": "revenuecat-key",
            "POSTHOG_API_KEY": "posthog-key"
        ])

        #expect(configuration.supabaseUrl == MerianEnvironment.fallbackSupabaseURL)
        #expect(configuration.supabaseAnonKey == "anon-key")
        #expect(!configuration.hasSupabaseConfiguration)
        #expect(configuration.issues.contains(.invalidSupabaseURL("not a valid url")))
    }

    @Test func cleartextOrCredentialedSupabaseURLFallsBack() {
        for unsafeURL in [
            "http://project.supabase.co",
            "https://user:secret@project.supabase.co"
        ] {
            let configuration = MerianEnvironment.load(infoDictionary: [
                "SUPABASE_URL": unsafeURL,
                "SUPABASE_ANON_KEY": "anon-key",
                "REVENUECAT_API_KEY": "revenuecat-key",
                "POSTHOG_API_KEY": "posthog-key"
            ])

            #expect(
                configuration.supabaseUrl
                    == MerianEnvironment.fallbackSupabaseURL
            )
            #expect(!configuration.hasSupabaseConfiguration)
            #expect(
                configuration.issues.contains(.invalidSupabaseURL(unsafeURL))
            )
        }
    }

    @Test func validConfigurationTrimsValuesAndReportsNoIssues() {
        let configuration = MerianEnvironment.load(infoDictionary: [
            "SUPABASE_URL": " https://project.supabase.co ",
            "SUPABASE_ANON_KEY": " anon-key ",
            "REVENUECAT_API_KEY": " revenuecat-key ",
            "POSTHOG_API_KEY": " posthog-key "
        ])

        #expect(configuration.supabaseUrl == "https://project.supabase.co")
        #expect(configuration.supabaseAnonKey == "anon-key")
        #expect(configuration.revenueCatApiKey == "revenuecat-key")
        #expect(configuration.postHogApiKey == "posthog-key")
        #expect(configuration.hasSupabaseConfiguration)
        #expect(configuration.issues.isEmpty)
    }

    @Test func debugSimulatorWarnsAboutProductionSupabaseByDefault() {
        let configuration = MerianEnvironment.load(
            infoDictionary: [
                "SUPABASE_URL": "https://\(MerianEnvironment.productionSupabaseHost)",
                "SUPABASE_ANON_KEY": "anon-key",
                "REVENUECAT_API_KEY": "revenuecat-key",
                "POSTHOG_API_KEY": "posthog-key"
            ],
            environment: [:],
            runtime: MerianEnvironment.RuntimeContext(
                isDebug: true,
                isSimulator: true
            )
        )

        #expect(
            configuration.supabaseUrl
                == "https://\(MerianEnvironment.productionSupabaseHost)"
        )
        #expect(configuration.hasSupabaseConfiguration)
        #expect(configuration.issues.contains(
            .productionSupabaseInDebugSimulator(
                MerianEnvironment.productionSupabaseHost
            )
        ))
    }

    @Test func debugSimulatorAllowsExplicitProductionSmokeOverride() {
        let configuration = MerianEnvironment.load(
            infoDictionary: [
                "SUPABASE_URL": "https://\(MerianEnvironment.productionSupabaseHost)",
                "SUPABASE_ANON_KEY": "anon-key",
                "REVENUECAT_API_KEY": "revenuecat-key",
                "POSTHOG_API_KEY": "posthog-key"
            ],
            environment: [
                "MERIAN_ALLOW_PRODUCTION_SUPABASE_IN_DEBUG_SIMULATOR": "1"
            ],
            runtime: MerianEnvironment.RuntimeContext(
                isDebug: true,
                isSimulator: true
            )
        )

        #expect(
            configuration.supabaseUrl
                == "https://\(MerianEnvironment.productionSupabaseHost)"
        )
        #expect(configuration.hasSupabaseConfiguration)
        #expect(configuration.issues.isEmpty)
    }

    @Test func debugSimulatorAllowsNonProductionSupabaseProjects() {
        let configuration = MerianEnvironment.load(
            infoDictionary: [
                "SUPABASE_URL": "https://merian-staging.supabase.co",
                "SUPABASE_ANON_KEY": "anon-key",
                "REVENUECAT_API_KEY": "revenuecat-key",
                "POSTHOG_API_KEY": "posthog-key"
            ],
            environment: [:],
            runtime: MerianEnvironment.RuntimeContext(
                isDebug: true,
                isSimulator: true
            )
        )

        #expect(configuration.supabaseUrl == "https://merian-staging.supabase.co")
        #expect(configuration.hasSupabaseConfiguration)
        #expect(configuration.issues.isEmpty)
    }
}
