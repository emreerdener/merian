import Foundation
import os

/// Outbox confirmation and cloud-deletion requests; queue and recovery state stay with their callers.
extension MerianNetworkClient {
    /// Confirms the owner's scan, including optional ingestion state and bounded owner-row recovery.
    func checkScanStatusDetails(
        scanId: String,
        requiredVideoCount: Int? = nil,
        recoveryScan: OwnedScanRecoveryPayload? = nil
    ) async throws -> ScanStatusResponse {
        try validateEndpointConfiguration("check-scan-status")
        var payload: [String: Any] = ["scan_id": scanId]
        if let requiredVideoCount, requiredVideoCount > 0 {
            payload["required_video_count"] = requiredVideoCount
        }
        if let recoveryScan {
            let recoveryData = try JSONEncoder().encode(recoveryScan)
            guard let recoveryObject = try JSONSerialization.jsonObject(with: recoveryData) as? [String: Any] else {
                throw MerianError.invalidResponse
            }
            payload["recovery_scan"] = recoveryObject
        }
        let expectedAuthUserID = recoveryScan.flatMap {
            UUID(uuidString: $0.userId)
        }
        let data = try await performAuthenticatedJSONDataPost(
            function: "check-scan-status",
            payload: payload,
            expectedAuthUserID: expectedAuthUserID
        )
        return try ScanLifecycleResponseDecoder.status(from: data, expectedScanID: scanId)
    }

    func checkScanStatuses(_ requirements: [String: Int]) async throws -> [String: ScanStatusResponse] {
        guard !requirements.isEmpty else { return [:] }
        var expectedScanIDs: [String: String] = [:]
        for scanID in requirements.keys {
            let normalized = scanID
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty,
                  expectedScanIDs.updateValue(scanID, forKey: normalized) == nil else {
                throw MerianError.invalidResponse
            }
        }
        try validateEndpointConfiguration("check-scan-status")
        let scans = requirements.map { requirement in
            var payload: [String: Any] = ["scan_id": requirement.key]
            let requiredVideoCount = requirement.value
            if requiredVideoCount > 0 {
                payload["required_video_count"] = requiredVideoCount
            }
            return payload
        }
        let data = try await performAuthenticatedJSONDataPost(
            function: "check-scan-status",
            payload: ["scans": scans]
        )
        return try ScanLifecycleResponseDecoder.statuses(from: data, expectedScanIDs: expectedScanIDs)
    }

    /// Compatibility wrapper for older callers that only need "found" / "not_found".
    func checkScanStatus(scanId: String, requiredVideoCount: Int? = nil) async throws -> String {
        let response = try await checkScanStatusDetails(
            scanId: scanId,
            requiredVideoCount: requiredVideoCount
        )
        return response.status.rawValue
    }

    func deleteScan(scanId: String) async throws {
        let data = try await performAuthenticatedJSONDataPost(
            function: "delete-scan",
            payload: ["scanId": scanId]
        )
        try ScanLifecycleResponseDecoder.confirmDeletion(from: data)
        MerianLog.network.debug("Scan deleted: \(scanId, privacy: .private)")
    }
}
