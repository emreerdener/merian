import Foundation
import SwiftData

/// Coordinates launch-time SwiftData store recovery without touching account
/// identity. Focused models, policies, and services define the work behind this
/// source-compatible façade.
///
/// Store recovery is intentionally narrow. It may quarantine or archive local
/// SwiftData files, but it must never clear Keychain, Supabase auth sessions,
/// device identity, or cloud ownership state.
enum ModelStoreRecoveryCoordinator {
    /// Preserves the location selected by shipped builds that relied on
    /// SwiftData's automatic App Group behavior. Extensions must not open this
    /// store; moving it to a private container requires a data-preserving
    /// rollout.
    static func productionStoreConfiguration(
        for schema: Schema
    ) -> ModelConfiguration {
        ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            groupContainer: .automatic,
            cloudKitDatabase: .automatic
        )
    }

    static func defaultStoreURL() -> URL {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        return productionStoreConfiguration(for: schema).url
    }
}
