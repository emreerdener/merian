import Foundation

enum ConsentHandoffError: LocalizedError {
    case activeAccountChanged
    case ledgerPersistenceFailed

    var errorDescription: String? {
        switch self {
        case .activeAccountChanged:
            return "The active account changed during consent migration."
        case .ledgerPersistenceFailed:
            return "The migrated consent ledger could not be persisted."
        }
    }
}

enum ConsentPersistenceError: LocalizedError {
    case storedLedgerUnavailable
    case revocationIntentInvalid
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .storedLedgerUnavailable:
            return "Naturebook could not safely access your saved consent record. Please try again."
        case .revocationIntentInvalid:
            return "Naturebook could not verify the saved analytics withdrawal. Analytics will remain off."
        case .encodingFailed:
            return "Naturebook could not prepare your consent record for secure storage."
        }
    }
}
