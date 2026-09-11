enum ComplimentaryScanDisplayState: Equatable {
    case available(scansRemaining: Int)
    case exhausted

    var scansRemaining: Int {
        switch self {
        case .available(let scansRemaining):
            scansRemaining
        case .exhausted:
            0
        }
    }

    var hasAccess: Bool {
        switch self {
        case .available:
            true
        case .exhausted:
            false
        }
    }

    var isExhausted: Bool {
        self == .exhausted
    }
}
