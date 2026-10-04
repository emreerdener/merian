import Foundation

@MainActor
struct LibrarySignOutRecoveryCoordinator {
    struct Dependencies {
        let currentSession: () -> AuthTransitionSession?
        let clearSourceSession: () async -> Bool
        let clearLibrary: () -> Bool
        let createDestination: () async -> AuthTransitionSession?
        let completePurchases: (UUID) async -> Bool
    }

    let store: LibrarySignOutJournalStore
    let dependencies: Dependencies

    /// Once committed, cancellation leaves the journal in place. Each step is
    /// restartable and must prove its postcondition before advancing the record.
    func resume() async -> Bool {
        do {
            guard var journal = try store.load() else { return true }
            if journal.phase == .committed {
                if let session = dependencies.currentSession() {
                    guard session.userID == journal.sourceUserID else { return false }
                }
                // An empty in-memory SDK snapshot is not evidence of durable
                // sign-out. Always execute and verify local session removal.
                guard await dependencies.clearSourceSession(),
                      dependencies.currentSession() == nil else { return false }
                journal.phase = .sourceCleared
                try store.save(journal)
            }
            if journal.phase == .sourceCleared {
                guard dependencies.currentSession() == nil,
                      dependencies.clearLibrary() else { return false }
                journal.phase = .libraryCleared
                try store.save(journal)
            }
            if journal.phase == .libraryCleared {
                // An SDK-persisted anonymous session recovers a lost local
                // journal write. An unrecorded server-only identity cannot be
                // recovered by the current Auth protocol.
                let destination: AuthTransitionSession?
                if let current = dependencies.currentSession() {
                    destination = current
                } else {
                    destination = await dependencies.createDestination()
                }
                guard let destination, destination.isAnonymous,
                      destination.userID != journal.sourceUserID else { return false }
                journal.destinationUserID = destination.userID
                journal.phase = .destinationCreated
                try store.save(journal)
            }
            guard let destinationID = journal.destinationUserID,
                  dependencies.currentSession() == AuthTransitionSession(userID: destinationID, isAnonymous: true),
                  await dependencies.completePurchases(destinationID),
                  dependencies.currentSession() == AuthTransitionSession(userID: destinationID, isAnonymous: true) else {
                return false
            }
            try store.clear()
            return true
        } catch {
            return false
        }
    }
}
