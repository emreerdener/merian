import Foundation
import SwiftData

/// These failures cannot safely enter another persistent attempt or archive.
enum StoreBootstrapBoundaryFailure: Error {
    case configuration
    case ownership
    case indeterminateConstruction
}

@MainActor
fileprivate final class StartupConstructionProvenance {
    var denied = false
}

/// Ephemeral construction provenance, not an operation or durable recovery grant.
/// No current native writer consumes this value.
@MainActor
struct NativeReleaseStartupAdmission {
    private let container: ModelContainer
    private let storeURL: URL
    private let binding: SharedMediaStoreReadFence.Binding
    private let provenance: StartupConstructionProvenance

    fileprivate init(container: ModelContainer, storeURL: URL,
                     binding: SharedMediaStoreReadFence.Binding, provenance: StartupConstructionProvenance) {
        self.container = container
        self.storeURL = storeURL
        self.binding = binding
        self.provenance = provenance
    }

    func require(container candidate: ModelContainer, fence: SharedMediaStoreReadFence) throws {
        guard !provenance.denied, candidate === container, candidate.configurations.count == 1,
              let configuration = candidate.configurations.first,
              !configuration.isStoredInMemoryOnly, configuration.url == storeURL,
              try fence.binding() == binding else {
            throw StoreBootstrapBoundaryFailure.ownership
        }
    }
}

/// One exact production configuration and one held cooperative fence, spanning
/// metadata, construction, classified recovery, archive and replacement.
@MainActor
final class PersistentStoreBootstrapSession {
    let schema: Schema
    let configuration: ModelConfiguration
    let fence: SharedMediaStoreReadFence
    private(set) var attempts = 0
    private let provenance = StartupConstructionProvenance()
    private var denied: Bool {
        get { provenance.denied }
        set { provenance.denied = newValue }
    }
    private var invalidated = false
    private weak var firstContainer: ModelContainer?
    #if DEBUG
    private var beforeAttempt: ((Int) throws -> Void)?
    #endif

    var storeURL: URL { configuration.url }

    static func production() throws -> PersistentStoreBootstrapSession {
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration = ModelStoreRecoveryCoordinator.productionStoreConfiguration(for: schema)
        guard configuration.groupAppContainerIdentifier == "group.app.merian.shared",
              let anchor = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.app.merian.shared"
              ) else { throw StoreBootstrapBoundaryFailure.configuration }
        return try PersistentStoreBootstrapSession(schema: schema, configuration: configuration,
                                                  anchor: anchor)
    }

    private init(schema: Schema, configuration: ModelConfiguration, anchor: URL,
                 synchronization: SharedMediaFenceSynchronization = .init()) throws {
        guard !configuration.isStoredInMemoryOnly, configuration.allowsSave,
              configuration.cloudKitContainerIdentifier == nil else {
            throw StoreBootstrapBoundaryFailure.configuration
        }
        self.schema = schema
        self.configuration = configuration
        do {
            fence = try SharedMediaStoreReadFence(store: configuration.url, access: .sharedWriter,
                                                  creationAnchor: anchor, synchronization: synchronization)
            try fence.check()
        } catch { throw StoreBootstrapBoundaryFailure.ownership }
    }

    #if DEBUG
    /// Hermetic disk fixtures only; production has no arbitrary configuration entry.
    static func fixture(schema: Schema, storeURL: URL, anchor: URL,
                        synchronization: SharedMediaFenceSynchronization = .init(),
                        beforeAttempt: ((Int) throws -> Void)? = nil) throws -> PersistentStoreBootstrapSession {
        guard TestExecutionCoordinator.isRunningTests,
              SharedMediaNativeEligibility.fixtureLocation(anchor),
              SharedMediaNativeEligibility.fixtureLocation(storeURL) else {
            throw StoreBootstrapBoundaryFailure.configuration
        }
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        let session = try PersistentStoreBootstrapSession(schema: schema, configuration: configuration,
                                                         anchor: anchor, synchronization: synchronization)
        session.beforeAttempt = beforeAttempt
        return session
    }
    #endif

    func check() throws {
        guard !invalidated else { throw StoreBootstrapBoundaryFailure.ownership }
        do { try fence.check() }
        catch {
            invalidated = true
            denied = true
            throw StoreBootstrapBoundaryFailure.ownership
        }
    }

    func construct(_ body: () throws -> ModelContainer) throws -> ModelContainer {
        try check()
        attempts += 1
        if attempts > 1 { denied = true }
        do {
            #if DEBUG
            try beforeAttempt?(attempts)
            #endif
            let container = try body()
            try check()
            guard container.configurations.count == 1,
                  let actual = container.configurations.first,
                  actual == configuration else { throw StoreBootstrapBoundaryFailure.configuration }
            if attempts == 1 && !denied { firstContainer = container }
            return container
        } catch {
            denied = true
            try check()
            if error is StoreBootstrapBoundaryFailure { invalidated = true }
            throw error
        }
    }

    func requireRecoverable(_ error: Error) throws {
        denied = true
        if error is StoreBootstrapBoundaryFailure {
            invalidated = true
            throw error
        }
        try check()
    }

    func recover<T>(_ body: () throws -> T) throws -> T {
        denied = true
        try check()
        do {
            let result = try body()
            try check()
            return result
        } catch {
            try requireRecoverable(error)
            throw error
        }
    }

    func admission(for container: ModelContainer) throws -> NativeReleaseStartupAdmission? {
        try check()
        guard attempts == 1, !denied, firstContainer === container else { return nil }
        return NativeReleaseStartupAdmission(container: container, storeURL: storeURL,
                                             binding: try fence.binding(), provenance: provenance)
    }
}
