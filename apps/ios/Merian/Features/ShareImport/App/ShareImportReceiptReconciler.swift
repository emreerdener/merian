import Foundation
import SwiftData
import UIKit

@MainActor
enum ShareImportReceiptReconciler {
    static func reconcileIfNeeded(
        modelContext: ModelContext,
        scanRepository: ScanRepository
    ) async {
        let snapshot = ShareImportReceiptStore.load()
        let activeReceipts = snapshot.receipts.filter { $0.status == .queued }
        guard !activeReceipts.isEmpty else { return }

        UserDefaults.standard.set(Date(), forKey: UserDefaultsKeys.lastHistoricalSyncDate)
        await scanRepository.syncHistoricalScansDown(modelContext: modelContext)

        var resolvedScanIds = Set<String>()
        for receipt in activeReceipts {
            var descriptor = FetchDescriptor<LocalScanRecord>(
                predicate: #Predicate { $0.id == receipt.scanId }
            )
            descriptor.fetchLimit = 1

            guard let record = try? modelContext.fetch(descriptor).first else {
                continue
            }

            record.hasBeenViewed = false
            resolvedScanIds.insert(receipt.scanId)
        }

        guard !resolvedScanIds.isEmpty else { return }

        do {
            try modelContext.save()
            AppSettings.shared.hasUnseenScan = true
            PushNotificationManager.shared.setBadgeCount(1)
            ShareImportReceiptStore.remove(scanIds: resolvedScanIds)
        } catch {
            modelContext.rollback()
        }
    }
}
