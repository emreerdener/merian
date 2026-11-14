import CryptoKit
import Foundation

/// Strict private result encoding with frozen V1/V2 compatibility rules. This proves byte/schema consistency only;
/// the caller must authenticate the original acquisition and retain its fences.
struct InitialRetainedResult: Sendable {
    typealias Value = InitialAnalysisCanonical.Value
    enum ApplicationFailure: Error, Equatable { case provenanceStorageLimit }
    let reference: Data, result: Data, provenance: Data
    let resultDigest: String, provenanceDigest: String

    init(reference: Data, result: Data, provenance: Data, resultDigest: String, provenanceDigest: String,
         expectedReference: Data, originalProvenance: Data) throws {
        guard reference.count <= 4096, expectedReference.count <= 4096,
              result.count <= 1_048_576, provenance.count <= 65_536, originalProvenance.count <= 65_536,
              resultDigest.utf8.count == 64, provenanceDigest.utf8.count == 64,
              Self.matches(resultDigest, pattern: "^[0-9a-f]{64}$"),
              Self.matches(provenanceDigest, pattern: "^[0-9a-f]{64}$"),
              reference == expectedReference, try Self.requestedProvenanceMatches(provenance, originalProvenance),
              let rules = Self.rules else { throw InitialAnalysisCanonical.Invalid.document }
        let ref = try Self.referenceFields(reference)
        let body = try Self.closed(InitialAnalysisCanonical.parse(result), keys: ["version", "state", "scan_id",
            "invocation_id", "submission_digest", "config_digest", "funding_binding_digest", "provider_usage", "data"])
        guard body["version"]?.integer == 1, body["state"]?.string == "validated_success" else { throw InitialAnalysisCanonical.Invalid.document }
        for key in ["scan_id", "invocation_id", "submission_digest", "config_digest", "funding_binding_digest"] {
            guard try Self.equal(body[key], ref[key]) else { throw InitialAnalysisCanonical.Invalid.document }
        }
        let original = try InitialAnalysisCanonical.parse(originalProvenance)
        var nodes = 0
        try Self.validate(original, rule: rules.provenance, depth: 0, nodes: &nodes)
        guard let data = body["data"], let fields = data.object else { throw InitialAnalysisCanonical.Invalid.document }
        nodes = 0; try Self.validate(data, rule: rules.data, depth: 0, nodes: &nodes)
        try Self.primarySemantics(fields)
        guard try Self.equal(fields["scan_id"], ref["scan_id"]),
              let embedded = fields["identification_provenance"],
              try InitialAnalysisCanonical.encode(embedded) == provenance,
              let provider = embedded.object?["provider"]?.string, let usage = body["provider_usage"] else {
            throw InitialAnalysisCanonical.Invalid.document
        }
        if embedded.object?["version"]?.integer == 3 {
            guard embedded.object?["model"]?.string == "gemini-3.8-flash",
                  embedded.object?["returned_model"]?.string == "gemini-3.8-flash" else { throw InitialAnalysisCanonical.Invalid.document }
        }
        try Self.usage(usage, provider: provider)
        guard Self.digest("result", result) == resultDigest,
              Self.digest("result-provenance", provenance) == provenanceDigest else { throw InitialAnalysisCanonical.Invalid.document }
        self.reference = reference; self.result = result; self.provenance = provenance
        self.resultDigest = resultDigest; self.provenanceDigest = provenanceDigest
    }

    private static func requestedProvenanceMatches(_ received: Data, _ requested: Data) throws -> Bool {
        if received == requested { return true }
        guard var left = try InitialAnalysisCanonical.parse(received).object,
              var right = try InitialAnalysisCanonical.parse(requested).object,
              left["version"]?.integer == 3, right["version"]?.integer == 3,
              left["model"]?.string == "gemini-3.8-flash",
              left["returned_model"]?.string == "gemini-3.8-flash",
              right["returned_model"]?.isNull == true || right["returned_model"]?.string == "gemini-3.8-flash" else { return false }
        left.removeValue(forKey: "returned_model"); right.removeValue(forKey: "returned_model")
        return try InitialAnalysisCanonical.encode(.object(left)) == InitialAnalysisCanonical.encode(.object(right))
    }

    /// Projection input for the existing local-record factory. Numbers retain
    /// the frozen decimal-string representation; this is not a public DTO.
    var applicationFields: [String: Value] {
        get throws {
            guard let fields = try InitialAnalysisCanonical.parse(result).object?["data"]?.object else {
                throw InitialAnalysisCanonical.Invalid.document
            }
            return fields
        }
    }

    /// Stored domain provenance uses JSON numbers. Decode only with the frozen
    /// provenance rules; never round-trip through a later live API DTO.
    func applicationProvenance() throws -> Data {
        guard let rules = Self.rules else { throw InitialAnalysisCanonical.Invalid.document }
        let value = try InitialAnalysisCanonical.parse(provenance)
        let object = try Self.applicationJSON(value, rule: rules.provenance)
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= 2_048 else { throw ApplicationFailure.provenanceStorageLimit }
        return bytes
    }

    /// Retains server field spelling, null/absence and ordered arrays for the
    /// existing V3 baseline comparison, decoding only frozen numeric fields.
    func applicationFieldJSON(_ key: String) throws -> Data? {
        let fields = try applicationFields
        guard let value = fields[key], !value.isNull else { return nil }
        guard let rule = Self.rules?.data.fields?[key]?.contract else { throw InitialAnalysisCanonical.Invalid.document }
        let object = try Self.applicationJSON(value, rule: rule)
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed])
        guard bytes.count <= 1_048_576 else { throw InitialAnalysisCanonical.Invalid.document }
        return bytes
    }

    private static func applicationJSON(_ value: Value, rule: InitialRetainedResultRule) throws -> Any {
        if value.isNull { return NSNull() }
        if rule.kind == "union", let key = rule.discriminator,
           let version = value.object?[key]?.integer, let variant = rule.variants?[String(version)] {
            return try applicationJSON(value, rule: variant)
        }
        if rule.kind == "object", let object = value.object, let fields = rule.fields {
            return try object.reduce(into: [String: Any]()) { result, entry in
                guard let field = fields[entry.key] else { throw InitialAnalysisCanonical.Invalid.document }
                result[entry.key] = try applicationJSON(entry.value, rule: field.contract)
            }
        }
        if rule.kind == "array", let items = value.array, let item = rule.items {
            return try items.map { try applicationJSON($0, rule: item) }
        }
        if rule.kind == "number", let text = value.string, let number = Double(text), number.isFinite { return number }
        if rule.kind == "integer", let number = value.integer { return number }
        if rule.kind == "string", let text = value.string { return text }
        if rule.kind == "boolean", let flag = value.boolean { return flag }
        throw InitialAnalysisCanonical.Invalid.document
    }

    private static func referenceFields(_ bytes: Data) throws -> [String: Value] {
        let fields = try closed(InitialAnalysisCanonical.parse(bytes), keys: ["owner_id", "scan_id", "invocation_id",
            "result_evidence_id", "submission_digest", "config_digest", "funding_binding_digest"])
        for (key, value) in fields {
            let pattern = key.hasSuffix("_id") ? "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$" : "^[0-9a-f]{64}$"
            guard let text = value.string, matches(text, pattern: pattern) else { throw InitialAnalysisCanonical.Invalid.document }
        }
        return fields
    }
    private static func closed(_ value: Value, keys: Set<String>) throws -> [String: Value] {
        guard let fields = value.object, Set(fields.keys) == keys else { throw InitialAnalysisCanonical.Invalid.document }
        return fields
    }
    private static func equal(_ lhs: Value?, _ rhs: Value?) throws -> Bool {
        guard let lhs, let rhs else { return false }
        return try InitialAnalysisCanonical.encode(lhs) == InitialAnalysisCanonical.encode(rhs)
    }
    private static func digest(_ domain: String, _ bytes: Data) -> String {
        SHA256.hash(data: Data("merian.initial-analysis.\(domain).v1\n".utf8) + bytes).map { String(format: "%02x", $0) }.joined()
    }
    private static func matches(_ value: String, pattern: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: value, range: range)?.range == range
    }

    private static let rules = try? JSONDecoder().decode(InitialRetainedResultRules.self, from: Data(InitialRetainedResultSchema.json.utf8))

    private static func validate(_ value: Value, rule: InitialRetainedResultRule, depth: Int, nodes: inout Int) throws {
        nodes += 1
        guard nodes <= 4096, depth <= 12 else { throw InitialAnalysisCanonical.Invalid.document }
        if value.isNull {
            guard rule.nullable == true else { throw InitialAnalysisCanonical.Invalid.document }
            return
        }
        switch rule.kind {
        case "union":
            guard let discriminator = rule.discriminator, let version = value.object?[discriminator]?.integer,
                  let variant = rule.variants?[String(version)] else { throw InitialAnalysisCanonical.Invalid.document }
            try validate(value, rule: variant, depth: depth, nodes: &nodes)
        case "object":
            guard let object = value.object, object.count <= 128, let fields = rule.fields,
                  Set(object.keys).isSubset(of: Set(fields.keys)) else { throw InitialAnalysisCanonical.Invalid.document }
            for (key, field) in fields {
                if let child = object[key] { try validate(child, rule: field.contract, depth: depth + 1, nodes: &nodes) } else if field.required { throw InitialAnalysisCanonical.Invalid.document }
            }
        case "array":
            guard let items = value.array, let itemRule = rule.items,
                  items.count >= (rule.minItems ?? 0), items.count <= min(rule.maxItems ?? 512, 512) else { throw InitialAnalysisCanonical.Invalid.document }
            for item in items { try validate(item, rule: itemRule, depth: depth + 1, nodes: &nodes) }
        case "string":
            guard let text = value.string, text.utf16.count >= (rule.minLength ?? 0), text.utf16.count <= (rule.maxLength ?? Int.max),
                  rule.choices.map({ $0.contains(where: { Data($0.utf8) == Data(text.utf8) }) }) ?? true,
                  rule.pattern.map({ matches(text, pattern: $0) }) ?? true else { throw InitialAnalysisCanonical.Invalid.document }
        case "boolean":
            guard let flag = value.boolean, rule.constant.map({ $0 == flag }) ?? true else { throw InitialAnalysisCanonical.Invalid.document }
        case "integer", "number":
            let number: Double
            if rule.kind == "integer" {
                guard let integer = value.integer else { throw InitialAnalysisCanonical.Invalid.document }
                number = Double(integer)
            } else {
                guard let text = value.string, text.utf8.count <= 327,
                      matches(text, pattern: "^-?(0|[1-9][0-9]*)(\\.[0-9]*[1-9])?$"), text != "-0",
                      let parsed = Double(text), parsed.isFinite,
                      Data(decimal(parsed).utf8) == Data(text.utf8) else { throw InitialAnalysisCanonical.Invalid.document }
                number = parsed
            }
            guard let minimum = rule.minimum, let maximum = rule.maximum, number.isFinite,
                  number >= minimum, number <= maximum else { throw InitialAnalysisCanonical.Invalid.document }
        default: throw InitialAnalysisCanonical.Invalid.document
        }
    }

    /// Expand the shortest finite IEEE spelling without locale or exponent notation.
    /// Shared frozen-owner vectors qualify this independently of public DTO decoding.
    private static func decimal(_ number: Double) -> String {
        let parts = String(number).lowercased().split(separator: "e", omittingEmptySubsequences: false)
        var mantissa = String(parts[0])
        if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
        guard parts.count == 2, let exponent = Int(parts[1]) else { return mantissa }
        let sign = mantissa.hasPrefix("-") ? "-" : ""
        if !sign.isEmpty { mantissa.removeFirst() }
        let fragments = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        let digits = fragments.joined(), position = fragments[0].count + exponent
        if position <= 0 { return sign + "0." + String(repeating: "0", count: -position) + digits }
        if position >= digits.count { return sign + digits + String(repeating: "0", count: position - digits.count) }
        let offset = digits.index(digits.startIndex, offsetBy: position)
        return sign + String(digits[..<offset]) + "." + String(digits[offset...])
    }

    private static func primarySemantics(_ data: [String: Value]) throws {
        let required = data["identification_provenance"]?.object?["schema"]?.string == "merian_identify_primary_v1"
        guard required == (data["primary_identification"] != nil) else { throw InitialAnalysisCanonical.Invalid.document }
        guard let primary = data["primary_identification"]?.object else {
            guard !(data["candidates"]?.array ?? []).contains(where: { $0.object?["taxon_rank"] != nil }) else { throw InitialAnalysisCanonical.Invalid.document }
            return
        }
        guard try InitialAnalysisCanonical.encode(.object(primary)).count <= 4096,
              let resolution = primary["resolution"]?.string else { throw InitialAnalysisCanonical.Invalid.document }
        for key in ["scientific_name", "common_name"] {
            if let text = primary[key]?.string {
                let scalars = text.unicodeScalars
                guard let first = scalars.first, let last = scalars.last,
                      !scalars.contains(where: { $0.value <= 31 || $0.value == 127 }),
                      !trimScalar(first.value), !trimScalar(last.value) else { throw InitialAnalysisCanonical.Invalid.document }
            }
        }
        if ["species", "genus", "family"].contains(resolution) && primary["scientific_name"]?.isNull == true { throw InitialAnalysisCanonical.Invalid.document }
        if resolution == "unresolved_biological" && primary["scientific_name"]?.isNull != true { throw InitialAnalysisCanonical.Invalid.document }
        guard data["is_biological_subject"]?.boolean == (resolution != "non_biological"),
              try equal(data["scientific_name"], primary["scientific_name"]),
              try equal(data["common_name"], primary["common_name"]) else { throw InitialAnalysisCanonical.Invalid.document }
        if resolution == "species" {
            let candidates = data["candidates"]?.array ?? []
            guard candidates.count <= 2, candidates.allSatisfy({ $0.object?["taxon_rank"]?.string == "species" }) else { throw InitialAnalysisCanonical.Invalid.document }
            return
        }
        guard data["candidates"]?.isNull == true, data["pet_identification"]?.isNull == true,
              data["is_new_to_merian_dictionary"]?.boolean == false else { throw InitialAnalysisCanonical.Invalid.document }
        for key in ["gbif_taxon_key", "reference_image_url", "wikipedia_url", "wikipedia_overview", "species_insights", "iucn_red_list_status", "alternative_common_names"] {
            guard data[key] == nil || data[key]?.isNull == true else { throw InitialAnalysisCanonical.Invalid.document }
        }
        if resolution == "family", let genus = data["taxonomy"]?.object?["genus"], !genus.isNull { throw InitialAnalysisCanonical.Invalid.document }
    }
    private static func trimScalar(_ value: UInt32) -> Bool {
        [9, 10, 11, 12, 13, 32, 160, 5760, 8232, 8233, 8239, 8287, 12288, 65279].contains(value) || (8192...8202).contains(value)
    }
    private static func usage(_ value: Value, provider: String) throws {
        let tokens = ["input_tokens", "cached_tokens", "cache_write_tokens", "output_tokens", "candidate_tokens", "thinking_tokens", "tool_tokens", "total_tokens"]
        let fields = try closed(value, keys: Set(tokens + ["service_tier", "modality_breakdown"]))
        for key in tokens {
            guard let item = fields[key], item.isNull || item.integer.map({ (0...100_000_000).contains($0) }) == true else { throw InitialAnalysisCanonical.Invalid.document }
        }
        guard fields["service_tier"]?.isNull == true || fields["service_tier"]?.string == "default",
              ["openai", "gemini"].contains(provider), let breakdown = fields["modality_breakdown"] else { throw InitialAnalysisCanonical.Invalid.document }
        let categories = try closed(breakdown, keys: provider == "gemini" ? ["prompt", "cached", "candidates", "tool"] : [])
        for category in categories.values {
            guard let counts = category.object, Set(counts.keys).isSubset(of: ["text", "image", "audio", "video"]),
                  counts.values.allSatisfy({ $0.integer.map({ (0...100_000_000).contains($0) }) == true }) else { throw InitialAnalysisCanonical.Invalid.document }
        }
        guard try InitialAnalysisCanonical.encode(value).count <= 2048 else { throw InitialAnalysisCanonical.Invalid.document }
    }
}

/// Trusted generated rules may contain metadata omitted by this decoder.
/// Payload validation below always rejects unknown fields regardless of it.
private struct InitialRetainedResultRules: Decodable, Sendable { let data: InitialRetainedResultRule, provenance: InitialRetainedResultRule }
private struct InitialRetainedResultField: Decodable, Sendable { let contract: InitialRetainedResultRule, required: Bool }
private final class InitialRetainedResultRule: Decodable, Sendable {
    let kind: String
    let nullable: Bool?
    let fields: [String: InitialRetainedResultField]?
    let items: InitialRetainedResultRule?
    let variants: [String: InitialRetainedResultRule]?
    let discriminator: String?
    let minLength: Int?, maxLength: Int?, minItems: Int?, maxItems: Int?
    let minimum: Double?, maximum: Double?
    let pattern: String?, choices: [String]?, constant: Bool?
    enum CodingKeys: String, CodingKey {
        case kind, nullable, fields, items, variants, discriminator, minLength, maxLength, minItems, maxItems, minimum, maximum, pattern
        case choices = "enum", constant = "const"
    }
}
