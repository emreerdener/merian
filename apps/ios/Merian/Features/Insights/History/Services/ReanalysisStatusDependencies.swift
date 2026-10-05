import Foundation
import SwiftData

@MainActor
struct ReanalysisStatusAccess {
    var available: (String, ModelContainer) -> Bool
    var open: (String, ModelContainer) throws -> ReanalysisStatusDependencies

    /// Prepared only; ordinary Shell access remains nil.
    static var prepared: Self {
        Self(available: { id, container in
            guard let session = try? IdentificationHistorySession(observation: id, container: container) else { return false }
            defer { session.close() }
            guard let page = try? session.operationStatusPage(after: nil) else { return false }
            return offersPage(page)
        }, open: { id, container in
            try IdentificationHistorySession(observation: id, container: container).operationStatusDependencies
        })
    }
    static func offersPage(_ page: ObservationReanalysisOperationStatus.Page) -> Bool {
        // Omitted corrupt rows must not hide valid work on later bounded pages.
        !page.items.isEmpty || page.next != nil
    }
}

@MainActor
struct ReanalysisStatusDependencies {
    var page: (ObservationReanalysisOperationStatus.Cursor?) async throws -> ObservationReanalysisOperationStatus.Page
    var validate: () throws -> Void
    var isCurrent: () -> Bool
    var close: () -> Void
}

extension IdentificationHistorySession {
    func operationStatusPage(after cursor: ObservationReanalysisOperationStatus.Cursor?) throws -> ObservationReanalysisOperationStatus.Page {
        try check()
        let result = try ObservationReanalysisOperationStatus(account: cloud).page(
            observationID: ObservationHistoryPage.uuid(observation), ownerID: session.userID, after: cursor,
            container: container, isCurrent: { [self] in isCurrent() })
        try check()
        return result
    }
    var operationStatusDependencies: ReanalysisStatusDependencies {
        .init(page: { [self] cursor in try operationStatusPage(after: cursor) },
              validate: { [self] in try check() }, isCurrent: { [self] in isCurrent() }, close: { [self] in close() })
    }
}
