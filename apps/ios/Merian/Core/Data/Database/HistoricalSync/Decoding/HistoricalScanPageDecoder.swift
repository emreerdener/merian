import Foundation
import Supabase

enum HistoricalScanPageDecoder {
    private enum RequiredRowKey: String, CodingKey {
        case explore_posts
    }

    static func decode(
        _ data: Data,
        using decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
    ) throws -> HistoricalScanPageDecodeResult {
        let root = try JSONSerialization.jsonObject(with: data)
        guard let rows = root as? [Any] else {
            throw HistoricalScanPageContractError.invalidTopLevel
        }

        var responses: [HistoricalScanResponse] = []
        responses.reserveCapacity(rows.count)
        var rejectedRowCount = 0
        var firstRejectedCodingPath: String?

        for (index, row) in rows.enumerated() {
            do {
                if let object = row as? [String: Any],
                   !object.keys.contains(RequiredRowKey.explore_posts.rawValue) {
                    throw DecodingError.keyNotFound(
                        RequiredRowKey.explore_posts,
                        .init(
                            codingPath: [],
                            debugDescription:
                                "Historical scan projection omitted explore_posts."
                        )
                    )
                }
                let rowData = try JSONSerialization.data(withJSONObject: row)
                responses.append(
                    try decoder.decode(HistoricalScanResponse.self, from: rowData)
                )
            } catch {
                rejectedRowCount += 1
                if firstRejectedCodingPath == nil {
                    firstRejectedCodingPath = boundedCodingPath(
                        from: error,
                        fallbackIndex: index
                    )
                }
            }
        }

        return HistoricalScanPageDecodeResult(
            responses: responses,
            remoteRowCount: rows.count,
            rejectedRowCount: rejectedRowCount,
            firstRejectedCodingPath: firstRejectedCodingPath
        )
    }

    private static func boundedCodingPath(
        from error: Error,
        fallbackIndex: Int
    ) -> String {
        let codingPath: [CodingKey]
        switch error {
        case DecodingError.typeMismatch(_, let context),
             DecodingError.valueNotFound(_, let context),
             DecodingError.dataCorrupted(let context):
            codingPath = context.codingPath
        case DecodingError.keyNotFound(let key, let context):
            codingPath = context.codingPath + [key]
        default:
            codingPath = []
        }
        let path = codingPath.isEmpty
            ? "row[\(fallbackIndex)]"
            : codingPath.map(\.stringValue).joined(separator: ".")
        return String(path.prefix(256))
    }
}
