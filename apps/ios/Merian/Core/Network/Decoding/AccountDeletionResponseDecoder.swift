import Foundation

/// Applies the existing receipt rules without owning Auth, cleanup, or retry.
enum AccountDeletionResponseDecoder {
    enum Operation: Sendable {
        case intake(requiresRecoveryExpiry: Bool)
        case commit
        case recovery(acknowledge: Bool)
        case recoveryV2(acknowledge: Bool)
    }

    static func decode(
        _ data: Data,
        statusCode: Int,
        for operation: Operation,
        now: () -> Date = { Date() }
    ) throws -> AccountDeletionReceipt {
        let receipt: AccountDeletionReceipt
        do {
            receipt = try JSONDecoder().decode(AccountDeletionReceipt.self, from: data)
        } catch {
            throw MerianError.invalidResponse
        }

        switch operation {
        case .intake(let requiresRecoveryExpiry):
            guard receipt.success,
                  isAcceptedDeletion(receipt, statusCode: statusCode),
                  !requiresRecoveryExpiry ||
                    AccountDeletionRecoveryValidation.isValidExpiry(receipt.recoveryCapabilityExpiresAt, now: now) else {
                throw MerianError.invalidResponse
            }
        case .commit:
            guard receipt.success,
                  receipt.protocolVersion == 2,
                  isAcceptedDeletion(receipt, statusCode: statusCode),
                  AccountDeletionRecoveryValidation.isValidExpiry(receipt.recoveryCapabilityExpiresAt, now: now) else {
                throw MerianError.invalidResponse
            }
        case .recovery(let acknowledge):
            let timestampIsValid = receipt.recoveryAcknowledged == true
                ? AccountDeletionRecoveryValidation.isValidTimestamp(receipt.recoveryCapabilityExpiresAt)
                : AccountDeletionRecoveryValidation.isValidExpiry(receipt.recoveryCapabilityExpiresAt, now: now)
            guard statusCode == 200,
                  receipt.success,
                  isAcceptedRecoveryReceipt(
                      receipt,
                      allowsNotCommitted: false,
                      acknowledge: acknowledge
                  ),
                  timestampIsValid,
                  !acknowledge || receipt.recoveryAcknowledged == true else {
                throw MerianError.invalidResponse
            }
        case .recoveryV2(let acknowledge):
            let timestampIsValid = receipt.status == .notCommitted
                || receipt.recoveryAcknowledged == true
                ? AccountDeletionRecoveryValidation.isValidTimestamp(receipt.recoveryCapabilityExpiresAt)
                : AccountDeletionRecoveryValidation.isValidExpiry(receipt.recoveryCapabilityExpiresAt, now: now)
            guard statusCode == 200,
                  receipt.success,
                  receipt.protocolVersion == 2,
                  isAcceptedRecoveryReceipt(
                      receipt,
                      allowsNotCommitted: true,
                      acknowledge: acknowledge
                  ),
                  timestampIsValid,
                  !acknowledge || receipt.recoveryAcknowledged == true else {
                throw MerianError.invalidResponse
            }
        }
        return receipt
    }

    static func decodePreparation(
        _ data: Data,
        statusCode: Int,
        now: () -> Date = { Date() }
    ) throws -> AccountDeletionPreparationReceipt {
        let receipt: AccountDeletionPreparationReceipt
        do {
            receipt = try JSONDecoder().decode(
                AccountDeletionPreparationReceipt.self,
                from: data
            )
        } catch {
            throw MerianError.invalidResponse
        }

        guard statusCode == 200,
              receipt.success,
              receipt.status == .prepared,
              receipt.protocolVersion == 2,
              AccountDeletionRecoveryValidation.isValidExpiry(
                  receipt.recoveryCapabilityExpiresAt,
                  now: now
              ) else {
            throw MerianError.invalidResponse
        }
        return receipt
    }

    private static func isAcceptedDeletion(_ receipt: AccountDeletionReceipt, statusCode: Int) -> Bool {
        (receipt.status == .pending && statusCode == 202)
            || (receipt.status == .completed && statusCode == 200)
    }

    private static func isAcceptedRecoveryReceipt(
        _ receipt: AccountDeletionReceipt,
        allowsNotCommitted: Bool,
        acknowledge: Bool
    ) -> Bool {
        guard let recoveryAcknowledged = receipt.recoveryAcknowledged else {
            return false
        }
        if receipt.status == .pending || receipt.status == .completed {
            return true
        }
        return allowsNotCommitted
            && !acknowledge
            && receipt.status == .notCommitted
            && !receipt.manualProviderRevocationRequired
            && !recoveryAcknowledged
    }
}
