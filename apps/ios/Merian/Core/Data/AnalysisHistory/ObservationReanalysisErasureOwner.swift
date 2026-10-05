import Foundation
import SwiftData

/// Local-only coalesced recovery. No connectivity, account lease, provider work or retry timer.
@MainActor
final class ObservationReanalysisErasureOwner {
    private struct Request {
        let container: ModelContainer
        let isCurrent: @MainActor @Sendable () -> Bool
    }
    private let files: ObservationReanalysisFileStore
    private var requested: Request?
    private var task: Task<Void, Never>?

    init(files: ObservationReanalysisFileStore = .init(documents: .documentsDirectory)) { self.files = files }

    func drain(container: ModelContainer, isCurrent: @escaping @MainActor @Sendable () -> Bool) async {
        requested = Request(container: container, isCurrent: isCurrent)
        if let task { await task.value; return }
        let active = Task {
            while let request = requested {
                requested = nil
                await pass(request)
            }
            task = nil
        }
        task = active
        await active.value
    }

    private func pass(_ request: Request) async {
        var afterID = ""
        while request.isCurrent() && !Task.isCancelled {
            let jobs: [(String, ObservationReanalysisErasureReceipt?)]
            do {
                let context = ModelContext(request.container)
                let kind = OfflineJobKind.observationReanalysisErasure.rawValue, pending = OfflineJobStatus.pending.rawValue
                let cursor = afterID
                var query = FetchDescriptor<OfflineJobRecord>(predicate: #Predicate {
                    $0.kindRaw == kind && $0.statusRaw == pending && $0.id > cursor
                }, sortBy: [SortDescriptor(\.id)])
                query.fetchLimit = 64
                jobs = try context.fetch(query).map { ($0.id, try? ObservationReanalysisErasureReceipt.restore($0)) }
            } catch {
                MerianLog.data.error("Reanalysis cleanup discovery failed; retaining local receipts.")
                return
            }
            guard !jobs.isEmpty else { return }
            for (id, receipt) in jobs {
                afterID = id
                guard request.isCurrent(), !Task.isCancelled else { return }
                guard let receipt else { continue }
                do {
                    try await files.erase(child: receipt.childID, authorize: {
                        try ObservationReanalysisErasurePersistence.validate(receipt, container: request.container, isCurrent: request.isCurrent)
                    }, acknowledge: {
                        _ = try ObservationReanalysisErasurePersistence.validate(receipt, container: request.container,
                            isCurrent: request.isCurrent, complete: true)
                    })
                } catch {
                    MerianLog.data.error("Reanalysis cleanup remains pending for a later local recovery opportunity.")
                }
            }
            await Task.yield()
        }
    }
}
