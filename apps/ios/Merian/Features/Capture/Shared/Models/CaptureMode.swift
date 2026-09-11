/// All capture modes available from the Capture workspace.
///
/// Adding a case requires matching pager content, settings copy, persistence
/// migration behavior, and startup-mode coverage.
enum CaptureMode: String, CaseIterable {
    case visual
    case audio
    case describe

    var title: String {
        switch self {
        case .visual: "Scan"
        case .audio: "Record"
        case .describe: "Describe"
        }
    }

    var symbolName: String {
        switch self {
        case .visual: "viewfinder"
        case .audio: "waveform"
        case .describe: "text.bubble"
        }
    }

    /// Parses a comma-separated string into a safe Capture-mode sequence and
    /// appends any missing cases in canonical order.
    static func userOrder(from raw: String) -> [CaptureMode] {
        var decoded = raw
            .split(separator: ",")
            .compactMap { CaptureMode(rawValue: String($0)) }
        let missing = CaptureMode.allCases.filter { !decoded.contains($0) }
        decoded.append(contentsOf: missing)
        return decoded
    }
}
