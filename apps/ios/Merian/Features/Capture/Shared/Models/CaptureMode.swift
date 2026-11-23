/// All capture modes available from the Capture workspace.
///
/// Adding a case requires matching pager content, settings copy, persistence
/// migration behavior, and startup-mode coverage.
enum CaptureMode: String, CaseIterable {
    case visual
    case audio
    // Retained to decode historical settings/routes. Supporting text is now
    // edited in Field notes, never exposed as a primary capture mode.
    case describe

    static let availableModes: [CaptureMode] = [.visual, .audio]

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
    /// removes the retired Describe mode and duplicates, and appends any
    /// missing physical-media modes without changing their relative order.
    static func userOrder(from raw: String) -> [CaptureMode] {
        let requested = raw
            .split(separator: ",")
            .compactMap { CaptureMode(rawValue: String($0)) }
        var decoded: [CaptureMode] = []
        for mode in requested where availableModes.contains(mode) && !decoded.contains(mode) {
            decoded.append(mode)
        }
        let missing = availableModes.filter { !decoded.contains($0) }
        decoded.append(contentsOf: missing)
        return decoded
    }
}
