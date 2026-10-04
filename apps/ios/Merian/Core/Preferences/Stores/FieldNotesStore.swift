import Foundation

enum FieldNotesStore {
    private static func key(for scanId: String) -> String {
        UserDefaultsKeys.fieldNotesPrefix + scanId
    }

    static func fieldNotes(for scanId: String, userDefaults: UserDefaults = .standard) -> String? {
        let value = userDefaults.string(forKey: key(for: scanId))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func setFieldNotes(_ fieldNotes: String?, for scanId: String, userDefaults: UserDefaults = .standard) {
        let trimmed = fieldNotes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fieldNotes, trimmed?.isEmpty == false {
            userDefaults.set(fieldNotes, forKey: key(for: scanId))
        } else {
            userDefaults.removeObject(forKey: key(for: scanId))
        }
    }

    static func unrepresentedValueCount(
        scanNotes: [String: String], authoritativeScanIDs: Set<String> = [], userDefaults: UserDefaults = .standard
    ) -> Int {
        userDefaults.dictionaryRepresentation().keys.filter { key in
            guard key.hasPrefix(UserDefaultsKeys.fieldNotesPrefix) else { return false }
            let scanID = String(key.dropFirst(UserDefaultsKeys.fieldNotesPrefix.count))
            guard !authoritativeScanIDs.contains(scanID) else { return false }
            guard let note = fieldNotes(for: scanID, userDefaults: userDefaults) else { return true }
            return scanNotes[scanID] != note
        }.count
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        for key in userDefaults.dictionaryRepresentation().keys
        where key.hasPrefix(UserDefaultsKeys.fieldNotesPrefix) {
            userDefaults.removeObject(forKey: key)
        }
    }

    static func hasStoredValues(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(UserDefaultsKeys.fieldNotesPrefix)
        }
    }
}
