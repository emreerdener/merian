import Foundation
@testable import Merian
import Testing

@MainActor
@Suite(.serialized, .sharedProcessState(.offlineQueueManager))
struct ObservationVideoOutcomeReaderTests {
    @Test(arguments: ["normal", "before", "begin", "lease-before", "lease-after", "scope-after", "foreign", "malformed", "transport"])
    func exactReaderOwnsLeaseAcrossAwait(boundary: String) async throws {
        let (seed, saved) = try await ObservationVideoExecutionServiceTests().seed("held-consumed"); defer { seed.remove() }
        let bytes = try ObservationVideoCompletionTests().result(saved.work.request), identity = seed.preparation.identity
        var value = try ObservationHistoryStateTests().fixture()
        value["owner_id"] = identity.ownerID.uuidString.lowercased()
        value["observation_id"] = identity.observationID.uuidString.lowercased()
        value["selected_analysis_id"] = identity.sourceAnalysisID.uuidString.lowercased()
        var item = try #require(value["analysis"] as? [String: Any]); item["snapshot"] = String(decoding: bytes, as: UTF8.self); value["analysis"] = item
        if boundary == "foreign" { value["owner_id"] = UUID().uuidString.lowercased() }
        let response = boundary == "malformed" ? Data("{}".utf8) : try JSONSerialization.data(withJSONObject: value)
        var events: [String] = [], current = boundary != "lease-before", after = false
        let cloud = ObservationHistoryCloudClient(begin: { owner in
            events.append("begin"); #expect(owner == identity.ownerID)
            if boundary == "begin" { throw MerianError.invalidResponse }
            return .init(id: UUID(), session: .init(userID: owner, isAnonymous: false))
        }, isCurrent: { _ in current }, finish: { _ in events.append("finish") }, fetch: { _ in throw MerianError.invalidResponse },
        fetchState: { request in
            events.append("fetch")
            #expect(request.observation_id == identity.observationID.uuidString.lowercased())
            #expect(request.analysis_id == identity.analysisID.uuidString.lowercased())
            await Task.yield()
            if boundary == "transport" { throw URLError(.timedOut) }
            if boundary == "lease-after" { current = false }
            after = true; return response
        })
        let read = ObservationVideoExecutionService.Dependencies.reader(account: cloud)
        do {
            let result = try await read(saved, { if boundary == "before" { throw MerianError.invalidResponse } }, {
                #expect(after)
                if boundary == "scope-after" { throw MerianError.invalidResponse }
            })
            #expect(boundary == "normal" && result == bytes)
        } catch { #expect(boundary != "normal") }
        #expect(events.filter { $0 == "finish" }.count == (boundary == "before" || boundary == "begin" ? 0 : 1))
        #expect(events.contains("fetch") == (!["before", "begin", "lease-before"].contains(boundary)))
    }
}
