import Foundation
import Testing

@testable import Merian

@Suite("Scan Lifecycle Response Decoder")
struct ScanLifecycleResponseDecoderTests {
    @Test func singleIdentityAcceptsAbsentAndCaseInsensitiveRawMatches() throws {
        for json in [#"{"status":"found"}"#, #"{"status":"found","scan_id":null}"#,
                     #"{"status":"found","scan_id":"SCAN-A","job_attempt_count":0}"#] {
            let response = try ScanLifecycleResponseDecoder.status(from: Data(json.utf8), expectedScanID: "scan-a")
            #expect(response.isFound)
        }
        let rawMatch = try ScanLifecycleResponseDecoder.status(
            from: Data(#"{"status":"found","scan_id":" Scan-A "}"#.utf8), expectedScanID: " scan-a "
        )
        #expect(rawMatch.scanId == " Scan-A ")
        let emptyMatch = try ScanLifecycleResponseDecoder.status(
            from: Data(#"{"status":"found","scan_id":""}"#.utf8), expectedScanID: ""
        )
        #expect(emptyMatch.isFound)
    }

    @Test func singleIdentityDoesNotTrimOrAcceptForeignRows() throws {
        for id in ["scan-b", " scan-a", "scan-a ", "", "\nscan-a"] {
            let data = try JSONSerialization.data(withJSONObject: ["status": "found", "scan_id": id])
            #expect(throws: MerianError.invalidResponse) {
                try ScanLifecycleResponseDecoder.status(from: data, expectedScanID: "scan-a")
            }
        }
    }

    @Test func malformedSingleSuccessMapsToInvalidResponse() {
        for json in ["", "not-json", "null", "[]", "{}", #"{"status":true}"#,
                     #"{"status":"found","scan_id":42}"#,
                     #"{"status":"not_found","job_attempt_count":-1}"#,
                     #"{"status":"not_found","job_attempt_count":9223372036854775808}"#,
                     #"{"status":"found","job_status":"unknown"}"#] {
            #expect(throws: MerianError.invalidResponse) {
                try ScanLifecycleResponseDecoder.status(from: Data(json.utf8), expectedScanID: "scan-a")
            }
        }
    }

    @Test func bulkRowsMapNormalizedIDsBackToRawRequestKeys() throws {
        let data = Data("""
        {"results":[
          {"scan_id":" scan-b ","status":"not_found","job_status":"failed_terminal","complimentary_state":"released"},
          {"scan_id":"SCAN-A","status":"found","job_attempt_count":0,"complimentary_state":"consumed"}
        ]}
        """.utf8)
        let response = try ScanLifecycleResponseDecoder.statuses(
            from: data, expectedScanIDs: ["scan-a": " Scan-A ", "scan-b": "ScAn-B"]
        )
        #expect(Set(response.keys) == [" Scan-A ", "ScAn-B"])
        #expect(response[" Scan-A "]?.scanId == "SCAN-A")
        #expect(response[" Scan-A "]?.complimentaryState == .consumed)
        #expect(response["ScAn-B"]?.scanId == " scan-b ")
        #expect(response["ScAn-B"]?.jobStatus == .failed)
        #expect(response["ScAn-B"]?.complimentaryState == .released)
    }

    @Test func bulkRejectsMissingDuplicateForeignAndMalformedRows() {
        let invalidRows = [
            "[]",
            #"[{"scan_id":"scan-a","status":"found"}]"#,
            #"[{"scan_id":"scan-a","status":"found"},{"scan_id":"SCAN-A ","status":"found"}]"#,
            #"[{"scan_id":"scan-a","status":"found"},{"scan_id":"scan-c","status":"found"}]"#,
            #"[{"scan_id":"scan-a","status":"found"},{"status":"not_found"}]"#,
            #"[{"scan_id":"scan-a","status":"found"},{"scan_id":" ","status":"not_found"}]"#,
            #"[{"scan_id":"scan-a","status":"found"},{"scan_id":"scan-b","status":"not_found","job_attempt_count":-1}]"#,
            #"[{"scan_id":"scan-a","status":"found"},{"scan_id":"scan-b","status":"unknown"}]"#,
            #"[{"scan_id":"scan-a","status":"found"},{"scan_id":"scan-b","status":"found"},{"scan_id":"scan-c","status":"found"}]"#
        ]
        for rows in invalidRows {
            #expect(throws: MerianError.invalidResponse) {
                try ScanLifecycleResponseDecoder.statuses(
                    from: Data(#"{"results":\#(rows)}"#.utf8), expectedScanIDs: ["scan-a": "scan-a", "scan-b": "scan-b"]
                )
            }
        }
        for json in ["", "not-json", "[]", "{}", #"{"results":null}"#, #"{"results":{}}"#] {
            #expect(throws: MerianError.invalidResponse) {
                try ScanLifecycleResponseDecoder.statuses(from: Data(json.utf8), expectedScanIDs: ["scan-a": "scan-a"])
            }
        }
    }

    @Test func emptyBulkEnvelopeRemainsDecodableWithoutInventingRows() throws {
        let response = try ScanLifecycleResponseDecoder.statuses(from: Data(#"{"results":[]}"#.utf8), expectedScanIDs: [:])
        #expect(response.isEmpty)
    }

    @Test func deletionRequiresAnExplicitBooleanSuccess() {
        for json in ["", "not-json", "null", "[]", "{}", #"{"success":false}"#,
                     #"{"success":null}"#, #"{"success":1}"#, #"{"success":"true"}"#] {
            #expect(throws: MerianError.invalidResponse) {
                try ScanLifecycleResponseDecoder.confirmDeletion(from: Data(json.utf8))
            }
        }
    }

    @Test func confirmedDeletionIgnoresAdditiveFields() throws {
        for json in [#"{"success":true}"#, #"{"success":true,"message":"Synthetic confirmation","schema_version":99}"#] {
            try ScanLifecycleResponseDecoder.confirmDeletion(from: Data(json.utf8))
        }
    }
}
