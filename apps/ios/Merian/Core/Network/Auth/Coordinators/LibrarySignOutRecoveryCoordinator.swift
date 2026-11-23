import Foundation

@MainActor
struct LibrarySignOutRecoveryCoordinator {
    struct Dependencies {
        let currentSession: () -> AuthTransitionSession?
        let clearSourceSession: (LibrarySignOutJournal) async -> Bool
        let clearLibrary: (LibrarySignOutJournal) async -> Bool
        let createDestination: () async -> AuthTransitionSession?
        let completePurchases: (UUID) async -> Bool
    }

    let store: LibrarySignOutJournalStore
    let dependencies: Dependencies

    /// Once committed, cancellation leaves the journal in place. Each step is
    /// restartable and must prove its postcondition before advancing the record.
    func resume(preservePrimaryData: Bool = MerianEnvironment.isHistoryQualificationBuild) async -> Bool {
        guard !MerianEnvironment.isHistoryQualificationBuild, !preservePrimaryData else { return false }
        do {
            guard let stored = try store.load() else { return true }
            var journal = try store.upgradeForCleanup(stored)
            while journal.phase != .destinationCreated {
                let expected = journal
                guard try store.load() == expected else { return false }
                switch journal.phase {
                case .committed:
                    if let session = dependencies.currentSession(), session.userID != journal.sourceUserID { return false }
                    // Nil in memory does not prove durable SDK session removal.
                    guard await dependencies.clearSourceSession(expected),
                          dependencies.currentSession() == nil else { return false }
                    journal.phase = .sourceCleared
                case .sourceCleared:
                    guard dependencies.currentSession() == nil,
                          await dependencies.clearLibrary(expected),
                          dependencies.currentSession() == nil else { return false }
                    journal.phase = .libraryCleared
                case .libraryCleared:
                    // An existing anonymous session has no durable link to this
                    // operation. A lost destination write remains pending rather
                    // than adopting an unrelated replacement account.
                    guard dependencies.currentSession() == nil,
                          let destination = await dependencies.createDestination(), destination.isAnonymous,
                          destination.userID != journal.sourceUserID,
                          dependencies.currentSession() == destination else { return false }
                    journal.destinationUserID = destination.userID
                    journal.phase = .destinationCreated
                case .destinationCreated: return false // Handled after the loop.
                }
                // Never overwrite a replacement or removed journal after suspension.
                guard try store.load() == expected else { return false }
                try store.save(journal)
            }
            guard try store.load() == journal, let destinationID = journal.destinationUserID,
                  dependencies.currentSession() == AuthTransitionSession(userID: destinationID, isAnonymous: true),
                  await dependencies.completePurchases(destinationID),
                  try store.load() == journal,
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
