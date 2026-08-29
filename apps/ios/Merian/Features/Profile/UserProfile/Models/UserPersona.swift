public enum UserPersona: CaseIterable, Equatable {
    case observer
    case explorer
    case naturalist
    case scholar
    case apexObserver

    public init(speciesCount: Int) {
        switch speciesCount {
        case 0: self = .observer
        case 1..<10: self = .explorer
        case 10..<50: self = .naturalist
        case 50..<100: self = .scholar
        default: self = .apexObserver
        }
    }

    public var title: String {
        switch self {
        case .observer: return "New Observer"
        case .explorer: return "Casual Explorer"
        case .naturalist: return "Dedicated Naturalist"
        case .scholar: return "Verified Scholar"
        case .apexObserver: return "Apex Observer"
        }
    }

    public var description: String {
        switch self {
        case .observer:
            return "The viewfinder is ready. Step outside to log your first scan."
        case .explorer:
            return "Starting your collection. Learning the language of local flora and fauna."
        case .naturalist:
            return "Mapping local biodiversity and building a vibrant library."
        case .scholar:
            return "Curating a museum-grade archive of the natural world."
        case .apexObserver:
            return "An absolute authority on the ecosystem. Your collection is a masterpiece."
        }
    }

    public var imageName: String {
        switch self {
        case .observer: return "persona-observer"
        case .explorer: return "persona-explorer"
        case .naturalist: return "persona-naturalist"
        case .scholar: return "persona-scholar"
        case .apexObserver: return "persona-apex-observer"
        }
    }

    public var nextLevelThreshold: Int? {
        switch self {
        case .observer: return 1
        case .explorer: return 10
        case .naturalist: return 50
        case .scholar: return 100
        case .apexObserver: return nil
        }
    }

    public var nextLevelTitle: String? {
        switch self {
        case .observer: return UserPersona.explorer.title
        case .explorer: return UserPersona.naturalist.title
        case .naturalist: return UserPersona.scholar.title
        case .scholar: return UserPersona.apexObserver.title
        case .apexObserver: return nil
        }
    }
}
