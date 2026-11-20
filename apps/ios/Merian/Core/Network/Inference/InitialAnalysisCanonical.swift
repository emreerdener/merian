import Foundation

/// The private IC-1 byte grammar. This does not authorize submission or delivery.
/// Compare canonical UTF-8 bytes, never Swift's normalization-insensitive String equality.
enum InitialAnalysisCanonical {
    enum Invalid: Error { case document }

    indirect enum Value: Sendable {
        case null, boolean(Bool), integer(Int64), string(String)
        case array([Value]), object([String: Value])

        var object: [String: Value]? {
            if case let .object(value) = self { return value }
            return nil
        }
        var array: [Value]? {
            if case let .array(value) = self { return value }
            return nil
        }
        var string: String? {
            if case let .string(value) = self { return value }
            return nil
        }
        var integer: Int64? {
            if case let .integer(value) = self { return value }
            return nil
        }
        var boolean: Bool? {
            if case let .boolean(value) = self { return value }
            return nil
        }
        var isNull: Bool {
            if case .null = self { return true }
            return false
        }
    }

    static let maximumBytes = 1_048_576
    static let maximumInteger: Int64 = 9_007_199_254_740_991

    static func parse(_ data: Data) throws -> Value {
        try parseBounded(data, ceiling: maximumBytes)
    }

    /// Separate fixed transport envelope budget. Inner IC-1 documents still use
    /// parse/encode and retain the unchanged 1MiB limit.
    static func parseCompletionStatus(_ data: Data) throws -> Value {
        try parseBounded(data, ceiling: InitialCompletionDocuments.statusResponseMaximumBytes)
    }

    private static func parseBounded(_ data: Data, ceiling: Int) throws -> Value {
        guard data.count <= ceiling else { throw Invalid.document }
        var parser = Parser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        guard parser.offset == parser.bytes.count else { throw Invalid.document }
        // Reject duplicate keys, BOM, alternate escapes, number spellings and whitespace.
        guard try encodeBounded(value, ceiling: ceiling) == data else { throw Invalid.document }
        return value
    }

    static func encode(_ value: Value) throws -> Data {
        try encodeBounded(value, ceiling: maximumBytes)
    }

    private static func encodeBounded(_ value: Value, ceiling: Int) throws -> Data {
        var nodes = 0
        let text = try render(value, depth: 0, nodes: &nodes, ceiling: ceiling)
        let data = Data(text.utf8)
        guard data.count <= ceiling else { throw Invalid.document }
        return data
    }

    /// PostgreSQL JSONB adds one space after each object colon and container comma.
    static func jsonbSpacing(_ value: Value) -> Int {
        switch value {
        case let .array(items):
            return max(0, items.count - 1) + items.reduce(0) { $0 + jsonbSpacing($1) }
        case let .object(fields):
            return fields.count + max(0, fields.count - 1)
                + fields.values.reduce(0) { $0 + jsonbSpacing($1) }
        default: return 0
        }
    }

    private static func visit(_ depth: Int, nodes: inout Int) throws {
        nodes += 1
        guard depth <= 12, nodes <= 4096 else { throw Invalid.document }
    }

    private static func keyIsValid(_ key: String) -> Bool {
        let bytes = Array(key.utf8)
        guard let first = bytes.first, (97...122).contains(first), bytes.count <= 64 else { return false }
        return bytes.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    /// Foundation JSONSerialization strips a literal leading BOM inside strings.
    /// Parse the canonical grammar directly, retaining every validated UTF-8 byte.
    private struct Parser {
        let bytes: [UInt8]
        var offset = 0
        var nodes = 0

        mutating func value(depth: Int) throws -> Value {
            try visit(depth, nodes: &nodes)
            guard offset < bytes.count else { throw Invalid.document }
            switch bytes[offset] {
            case 110: try literal(Array("null".utf8)); return .null
            case 116: try literal(Array("true".utf8)); return .boolean(true)
            case 102: try literal(Array("false".utf8)); return .boolean(false)
            case 34: return .string(try string())
            case 91:
                offset += 1
                var items: [Value] = []
                if take(93) { return .array(items) }
                repeat {
                    guard items.count < 512 else { throw Invalid.document }
                    items.append(try value(depth: depth + 1))
                    if take(93) { return .array(items) }
                    guard take(44) else { throw Invalid.document }
                } while true
            case 123:
                offset += 1
                var fields: [String: Value] = [:]
                if take(125) { return .object(fields) }
                repeat {
                    guard fields.count < 128 else { throw Invalid.document }
                    let key = try string()
                    guard keyIsValid(key), fields[key] == nil, take(58) else { throw Invalid.document }
                    fields[key] = try value(depth: depth + 1)
                    if take(125) { return .object(fields) }
                    guard take(44) else { throw Invalid.document }
                } while true
            default:
                let start = offset
                _ = take(45)
                while offset < bytes.count, (48...57).contains(bytes[offset]) {
                    offset += 1
                    guard offset - start <= 17 else { throw Invalid.document }
                }
                guard offset > start,
                      // ASCII-only token; Int64 and final canonical byte equality reject malformed input.
                      // swiftlint:disable:next optional_data_string_conversion
                      let number = Int64(String(decoding: bytes[start..<offset], as: UTF8.self)),
                      number >= -maximumInteger, number <= maximumInteger else { throw Invalid.document }
                return .integer(number)
            }
        }

        private mutating func take(_ byte: UInt8) -> Bool {
            guard offset < bytes.count, bytes[offset] == byte else { return false }
            offset += 1
            return true
        }

        private mutating func literal(_ expected: [UInt8]) throws {
            guard bytes.count - offset >= expected.count,
                  bytes[offset..<(offset + expected.count)].elementsEqual(expected) else { throw Invalid.document }
            offset += expected.count
        }

        private mutating func string() throws -> String {
            guard take(34) else { throw Invalid.document }
            var contents: [UInt8] = []
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                if byte == 34 {
                    // Preserve literal FEFF; the next byte comparison rejects every UTF8 repair.
                    // swiftlint:disable:next optional_data_string_conversion
                    let text = String(decoding: contents, as: UTF8.self)
                    guard text.utf8.elementsEqual(contents) else { throw Invalid.document }
                    return text
                }
                guard byte >= 32 else { throw Invalid.document }
                if byte != 92 { contents.append(byte); continue }
                guard offset < bytes.count else { throw Invalid.document }
                let escaped = bytes[offset]
                offset += 1
                switch escaped {
                case 34, 92: contents.append(escaped)
                case 98: contents.append(8)
                case 116: contents.append(9)
                case 110: contents.append(10)
                case 102: contents.append(12)
                case 114: contents.append(13)
                case 117:
                    // Canonical JSON only uses unicode escapes for unnamed controls.
                    guard take(48), take(48), offset + 2 <= bytes.count,
                          // UInt8 accepts only a hex token; final canonical byte equality fixes spelling.
                          // swiftlint:disable:next optional_data_string_conversion
                          let code = UInt8(String(decoding: bytes[offset..<(offset + 2)], as: UTF8.self), radix: 16),
                          (1...31).contains(code), ![8, 9, 10, 12, 13].contains(code) else { throw Invalid.document }
                    offset += 2
                    contents.append(code)
                default: throw Invalid.document
                }
            }
            throw Invalid.document
        }
    }

    private static func quote(_ string: String) throws -> String {
        guard string.utf8.count <= maximumBytes else { throw Invalid.document }
        var result = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0: throw Invalid.document
            case 8: result += "\\b"
            case 9: result += "\\t"
            case 10: result += "\\n"
            case 12: result += "\\f"
            case 13: result += "\\r"
            case 34: result += "\\\""
            case 92: result += "\\\\"
            case 1...31: result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    private static func render(_ value: Value, depth: Int, nodes: inout Int, ceiling: Int) throws -> String {
        try visit(depth, nodes: &nodes)
        let text: String
        switch value {
        case .null: text = "null"
        case let .boolean(value): text = value ? "true" : "false"
        case let .integer(value):
            guard value >= -maximumInteger, value <= maximumInteger else { throw Invalid.document }
            text = String(value)
        case let .string(value): text = try quote(value)
        case let .array(values):
            guard values.count <= 512 else { throw Invalid.document }
            text = "[" + (try values.map { try render($0, depth: depth + 1, nodes: &nodes, ceiling: ceiling) }).joined(separator: ",") + "]"
        case let .object(fields):
            guard fields.count <= 128, fields.keys.allSatisfy(keyIsValid) else { throw Invalid.document }
            var parts: [String] = []
            for key in fields.keys.sorted() {
                guard let child = fields[key] else { throw Invalid.document }
                parts.append(try quote(key) + ":" + render(child, depth: depth + 1, nodes: &nodes, ceiling: ceiling))
            }
            text = "{" + parts.joined(separator: ",") + "}"
        }
        guard text.utf8.count <= ceiling else { throw Invalid.document }
        return text
    }
}
