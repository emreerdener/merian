import Foundation
import SwiftData

/// The common transaction core accepts either sealed capability. Cold recovery
/// cannot borrow fresh reserve/partial authority or replace the persisted epoch.
@MainActor
enum SharedMediaNativeAppPairAuthority {
    case fresh(SharedMediaNativeAppPairFileWitness)
    case recovery(SharedMediaNativeAppPairRecoveryWitness)

    var preparation: SharedMediaNativeAppPreparationWitness {
        switch self {
        case .fresh(let value): return value.preparation
        case .recovery(let value): return value.preparation
        }
    }
    var state: SharedMediaNativePairFileState {
        switch self {
        case .fresh(let value): return value.state
        case .recovery(let value): return value.state
        }
    }
    var binding: SharedMediaNativeBinding {
        switch self {
        case .fresh(let value): return value.binding
        case .recovery(let value): return value.binding
        }
    }
    var action: SharedMediaNativeAppPairAction {
        switch self {
        case .fresh(let value): return value.action
        case .recovery(let value): return value.action.transition
        }
    }
    func seal() throws {
        switch self {
        case .fresh(let value): try value.seal()
        case .recovery(let value): try value.seal()
        }
    }
    func beforeReadback() throws {
        switch self {
        case .fresh(let value): try value.beforeReadback()
        case .recovery(let value): try value.beforeReadback()
        }
    }
    func validate(_ container: ModelContainer) throws {
        switch self {
        case .fresh(let value): try value.validate(container)
        case .recovery(let value): try value.validate(container)
        }
    }
}
