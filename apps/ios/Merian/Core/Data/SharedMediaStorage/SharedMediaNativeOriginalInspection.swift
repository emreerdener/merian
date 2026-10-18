import Foundation

/// Complete read-only namespace/receipt inspection under the registered owner's
/// unchanged store fence. All queries return values; no constructor or save.
@MainActor
enum SharedMediaNativeOriginalInspection {
    static func run(reader: SharedMediaNativeOriginalReadback, io: SharedMediaNativeOriginalIO,
                    authority: SharedMediaNativeInspectionAuthority) async throws -> Bool {
        try authority.validate()
        var offset = 0, recovery = false
        while true {
            let page = try reader.page(offset: offset, inspection: authority)
            for entry in page {
                switch entry.receipt {
                case .completed(let request, let result):
                    try await io.verify(request: request, result: result, retirement: entry.retirement)
                    try authority.validate()
                    recovery = recovery || entry.retirement != nil
                case .reserved(let request), .held(let request):
                    if let closure = entry.pendingClosure {
                        try await io.verifyPending(request, closure: closure); try authority.validate()
                    }
                    recovery = true
                case .released: break
                }
            }
            if page.count < SharedMediaStoragePolicy.pageSize { break }
            let (next, overflow) = offset.addingReportingOverflow(page.count)
            guard !overflow else { throw SharedMediaStorageFailure.capacity }; offset = next
        }
        // Hash reads can suspend. Finish the reverse leaf join after all reads.
        try await io.visit { @MainActor leaf in try reader.verifyLeaf(leaf, inspection: authority) }
        try authority.validate()
        return try recovery || reader.hasPreparationAttempt(inspection: authority)
    }
}
