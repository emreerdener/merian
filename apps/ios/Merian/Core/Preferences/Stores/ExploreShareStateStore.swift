import Foundation

enum ExploreShareStateStore {
    struct ReconciliationSnapshot: Sendable {
        fileprivate let revision: UInt64
        fileprivate let storeIdentifier: ObjectIdentifier
    }

    private struct ReconciliationKey: Hashable {
        let storeIdentifier: ObjectIdentifier
        let scanId: String
    }

    private final class ReconciliationFence: @unchecked Sendable {
        private let lock = NSLock()
        private var nextRevision: UInt64 = 0
        private var lastRevisionByKey: [ReconciliationKey: UInt64] = [:]
        private var invalidatedRevisionByStore: [ObjectIdentifier: UInt64] = [:]

        func snapshot(for userDefaults: UserDefaults) -> ReconciliationSnapshot {
            lock.withLock {
                ReconciliationSnapshot(
                    revision: allocateRevision(),
                    storeIdentifier: ObjectIdentifier(userDefaults)
                )
            }
        }

        func setSharedPostId(
            _ postId: String?,
            for scanId: String,
            userDefaults: UserDefaults
        ) {
            lock.withLock {
                let reconciliationKey = ReconciliationKey(
                    storeIdentifier: ObjectIdentifier(userDefaults),
                    scanId: scanId
                )
                lastRevisionByKey[reconciliationKey] = allocateRevision()
                ExploreShareStateStore.writeSharedPostId(
                    postId,
                    for: scanId,
                    userDefaults: userDefaults
                )
            }
        }

        func reconcileSharedPostIds(
            _ postIdsByScanId: [String: String],
            forScanIds scanIds: [String],
            ifUnchangedSince snapshot: ReconciliationSnapshot,
            userDefaults: UserDefaults
        ) -> Set<String> {
            lock.withLock {
                let storeIdentifier = ObjectIdentifier(userDefaults)
                guard snapshot.storeIdentifier == storeIdentifier,
                      snapshot.revision > invalidatedRevisionByStore[
                          storeIdentifier,
                          default: 0
                      ] else {
                    return []
                }

                var changedScanIds = Set<String>()
                for scanId in Set(scanIds) {
                    let reconciliationKey = ReconciliationKey(
                        storeIdentifier: storeIdentifier,
                        scanId: scanId
                    )
                    guard lastRevisionByKey[reconciliationKey, default: 0]
                        <= snapshot.revision else {
                        continue
                    }

                    let currentPostId = ExploreShareStateStore.normalizedPostId(
                        userDefaults.string(
                            forKey: ExploreShareStateStore.key(for: scanId)
                        )
                    )
                    let expectedPostId = ExploreShareStateStore.normalizedPostId(
                        postIdsByScanId[scanId]
                    )
                    lastRevisionByKey[reconciliationKey] = snapshot.revision
                    guard currentPostId != expectedPostId else { continue }

                    ExploreShareStateStore.writeSharedPostId(
                        expectedPostId,
                        for: scanId,
                        userDefaults: userDefaults
                    )
                    changedScanIds.insert(scanId)
                }

                return changedScanIds
            }
        }

        func clearAll(userDefaults: UserDefaults) {
            lock.withLock {
                let storeIdentifier = ObjectIdentifier(userDefaults)
                invalidatedRevisionByStore[storeIdentifier] = allocateRevision()
                lastRevisionByKey = lastRevisionByKey.filter {
                    $0.key.storeIdentifier != storeIdentifier
                }
                for preferenceKey in userDefaults.dictionaryRepresentation().keys
                where preferenceKey.hasPrefix(
                    UserDefaultsKeys.sharedExplorePostIdPrefix
                ) {
                    userDefaults.removeObject(forKey: preferenceKey)
                }
            }
        }

        private func allocateRevision() -> UInt64 {
            nextRevision &+= 1
            return nextRevision
        }
    }

    private static let reconciliationFence = ReconciliationFence()

    private static func key(for scanId: String) -> String {
        UserDefaultsKeys.sharedExplorePostIdPrefix + scanId
    }

    private static func normalizedPostId(_ postId: String?) -> String? {
        let value = postId?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    static func sharedPostId(for scanId: String, userDefaults: UserDefaults = .standard) -> String? {
        normalizedPostId(userDefaults.string(forKey: key(for: scanId)))
    }

    static func setSharedPostId(_ postId: String?, for scanId: String, userDefaults: UserDefaults = .standard) {
        reconciliationFence.setSharedPostId(
            normalizedPostId(postId),
            for: scanId,
            userDefaults: userDefaults
        )
    }

    static func makeReconciliationSnapshot(
        userDefaults: UserDefaults = .standard
    ) -> ReconciliationSnapshot {
        reconciliationFence.snapshot(for: userDefaults)
    }

    @discardableResult
    static func reconcileSharedPostIds(
        _ postIdsByScanId: [String: String],
        forScanIds scanIds: [String],
        ifUnchangedSince snapshot: ReconciliationSnapshot,
        userDefaults: UserDefaults = .standard
    ) -> Set<String> {
        reconciliationFence.reconcileSharedPostIds(
            postIdsByScanId,
            forScanIds: scanIds,
            ifUnchangedSince: snapshot,
            userDefaults: userDefaults
        )
    }

    static func clearAll(userDefaults: UserDefaults = .standard) {
        reconciliationFence.clearAll(userDefaults: userDefaults)
    }

    static func hasStoredValues(
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        userDefaults.dictionaryRepresentation().keys.contains {
            $0.hasPrefix(UserDefaultsKeys.sharedExplorePostIdPrefix)
        }
    }

    private static func writeSharedPostId(
        _ postId: String?,
        for scanId: String,
        userDefaults: UserDefaults
    ) {
        if let postId {
            userDefaults.set(postId, forKey: key(for: scanId))
        } else {
            userDefaults.removeObject(forKey: key(for: scanId))
        }
    }
}
