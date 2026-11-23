import CoreFoundation
import Foundation

/// Local operation identity survives recovery-capability retirement. It grants
/// no server authority and is removed atomically with the accepted phase.
struct AccountDeletionCleanupMarker: Equatable {
    let phase: AccountDeletionLocalRecoveryState
    let operationID: UUID

    var storedValue: [String: Any] {
        ["version": 2, "phase": phase.rawValue, "operationID": operationID.uuidString.lowercased()]
    }

    static func decode(_ object: Any?) -> Self? {
        guard let value = object as? [String: Any],
              Set(value.keys) == ["version", "phase", "operationID"],
              let version = value["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: version.objCType)),
              version.int64Value == 2,
              let rawPhase = value["phase"] as? String,
              let phase = AccountDeletionLocalRecoveryState(rawValue: rawPhase),
              let rawID = value["operationID"] as? String,
              rawID.utf8.count == 36, let operationID = UUID(uuidString: rawID),
              operationID.uuidString.lowercased() == rawID else { return nil }
        return Self(phase: phase, operationID: operationID)
    }

    static func legacyState(_ object: Any?) -> AccountDeletionLocalRecoveryState? {
        if let value = object as? String { return AccountDeletionLocalRecoveryState(rawValue: value) }
        if let value = object as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID(), value.boolValue {
            return .cleanupPending
        }
        return nil
    }
}
