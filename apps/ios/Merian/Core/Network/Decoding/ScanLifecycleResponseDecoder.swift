import Foundation

/// Strict successful-response decoding, separate from transport and recovery policy.
enum ScanLifecycleResponseDecoder {
    static func status(from data: Data, expectedScanID: String) throws -> ScanStatusResponse {
        let response = try decode(ScanStatusResponse.self, from: data)
        guard response.scanId == nil ||
                response.scanId?.caseInsensitiveCompare(expectedScanID) == .orderedSame,
              response.jobAttemptCount.map({ $0 >= 0 }) ?? true else {
            throw MerianError.invalidResponse
        }
        return response
    }

    static func statuses(
        from data: Data,
        expectedScanIDs: [String: String]
    ) throws -> [String: ScanStatusResponse] {
        let response = try decode(BulkScanStatusResponse.self, from: data)
        guard response.results.count == expectedScanIDs.count else {
            throw MerianError.invalidResponse
        }

        var results: [String: ScanStatusResponse] = [:]
        for result in response.results {
            guard let returnedScanID = result.scanId?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                let requestedScanID = expectedScanIDs[returnedScanID.lowercased()],
                results[requestedScanID] == nil,
                result.jobAttemptCount.map({ $0 >= 0 }) ?? true else {
                throw MerianError.invalidResponse
            }
            results[requestedScanID] = result
        }
        guard results.count == expectedScanIDs.count else {
            throw MerianError.invalidResponse
        }
        return results
    }

    static func confirmDeletion(from data: Data) throws {
        let response = try decode(DeleteScanResponse.self, from: data)
        guard response.success else {
            throw MerianError.invalidResponse
        }
    }

    private static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw MerianError.invalidResponse
        }
    }

    private struct BulkScanStatusResponse: Decodable {
        let results: [ScanStatusResponse]
    }

    private struct DeleteScanResponse: Decodable {
        let success: Bool
    }
}
