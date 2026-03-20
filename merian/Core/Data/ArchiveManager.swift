import Foundation
import Photos
import SwiftUI
import SwiftData

@MainActor
class ArchiveManager: ObservableObject {
    static let shared = ArchiveManager()
    
    @Published var isStorageCriticallyLow: Bool = false
    @Published var isAuthorized: Bool = false
    
    private let diskSpaceThreshold: Int64 = 500 * 1024 * 1024 // 500MB
    private let albumName = "Merian"
    
    private init() {
        checkPermissions()
    }
    
    private func checkPermissions() {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        self.isAuthorized = (status == .authorized || status == .limited)
    }
    
    func requestPermissions() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        self.isAuthorized = (status == .authorized || status == .limited)
        return self.isAuthorized
    }
    
    func initiatePrePurgeSync(pendingImages: [URL]) async {
        let availableSpace = getAvailableDiskSpace()
        
        if availableSpace < diskSpaceThreshold {
            self.isStorageCriticallyLow = true
            HapticManager.shared.triggerErrorThump()
            return
        }
        
        self.isStorageCriticallyLow = false
        
        if !isAuthorized {
            let granted = await requestPermissions()
            if !granted {
                print("ArchiveManager: Photo library access denied. Cannot archive images.")
                return
            }
        }
        
        for imageUrl in pendingImages {
            do {
                try await downloadToLocalLibrary(url: imageUrl)
            } catch {
                print("ArchiveManager: Local archive failed for \(imageUrl): \(error.localizedDescription)")
            }
        }
    }
    
    func getAvailableDiskSpace() -> Int64 {
        do {
            let fileURL = URL(fileURLWithPath: NSHomeDirectory())
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let available = values.volumeAvailableCapacityForImportantUsage {
                return available
            }
        } catch {
            print("ArchiveManager: Failed to query true APFS space: \(error)")
        }
        return 0
    }
    
    private func downloadToLocalLibrary(url: URL) async throws {
        var tempFileURL: URL? = nil
        
        if !url.isFileURL {
            let (downloadedURL, response) = try await URLSession.shared.download(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            // Move from ephemeral network cache to a stable temporary boundary to prevent URLSession auto-destruct
            let stableURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            try? FileManager.default.removeItem(at: stableURL)
            try FileManager.default.moveItem(at: downloadedURL, to: stableURL)
            tempFileURL = stableURL
        }
        
        defer {
            if let fileToRemove = tempFileURL {
                try? FileManager.default.removeItem(at: fileToRemove)
            }
        }
        
        let resourceURL = tempFileURL ?? url
        
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, fileURL: resourceURL, options: nil)
        }
        
        print("ArchiveManager: Successfully archived image to device Photos.")
    }
    
    /// Evaluates aging Free Tier scans between 80-88 days old to permanently rescue payloads natively dropping from R2
    func evaluateAndRescueAgingScans(modelContext: ModelContext) {
        // Enforce the Free Tier constraint natively
        guard !RevenueCatManager.shared.isProActive else { return }
        
        let availableSpace = getAvailableDiskSpace()
        if availableSpace < diskSpaceThreshold {
            print("ArchiveManager: ASP rescue aborted - insufficient device partition boundary.")
            return
        }
        
        let now = Date()
        let calendar = Calendar.current
        guard let eightyDaysAgo = calendar.date(byAdding: .day, value: -80, to: now),
              let eightyEightDaysAgo = calendar.date(byAdding: .day, value: -88, to: now) else { return }
        
        let descriptor = FetchDescriptor<LocalScanRecord>(
            predicate: #Predicate { scan in
                scan.isLocallyArchived == false &&
                scan.timestamp <= eightyDaysAgo &&
                scan.timestamp >= eightyEightDaysAgo
            }
        )
        
        do {
            let agingScans = try modelContext.fetch(descriptor)
            guard !agingScans.isEmpty else { return }
            
            let container = modelContext.container
            let resourceIDs = agingScans.map { $0.persistentModelID }
            
            Task.detached(priority: .background) {
                let archiveActor = ArchiveDatabaseActor(modelContainer: container)
                await archiveActor.rescueTransfers(resourceIDs: resourceIDs)
            }
        } catch {
            print("ArchiveManager: Failed to evaluate offline sweeps bounds: \(error.localizedDescription)")
        }
    }
    /// Downloads global dataset backups natively protecting cellular bandwidth via strict file caching
    func downloadArchive(id: String, url: URL) async throws -> URL {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw URLError(.cannotCreateFile)
        }
        
        let filename = "dataset_archive_\(id).zip"
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
        return fileURL
    }
}

@ModelActor
actor ArchiveDatabaseActor {
    func rescueTransfers(resourceIDs: [PersistentIdentifier]) async {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        // Pre-calculate array of target UUID strings to naturally bypass N+1 network lookups
        var targetMappings: [PersistentIdentifier: String] = [:]
        for modelID in resourceIDs {
            if let record = self.modelContext.model(for: modelID) as? LocalScanRecord {
                targetMappings[modelID] = record.id
            }
        }
        
        let targetStrings = Array(targetMappings.values)
        guard !targetStrings.isEmpty else { return }
        
        struct BulkScanUrlResponse: Decodable {
            let id: String
            let image_storage_urls: [String]
        }
        
        var remoteUrlMap: [String: [String]] = [:]
        
        // Execute a single bulk query to extract all URLs in one O(1) payload
        do {
            let postgrestResponse = try await SupabaseManager.shared.client
                .from("scans")
                .select("id, image_storage_urls")
                .in("id", values: targetStrings)
                .execute()
                
            let decoder = JSONDecoder()
            let parsedCollection = try decoder.decode([BulkScanUrlResponse].self, from: postgrestResponse.data)
            
            for item in parsedCollection {
                remoteUrlMap[item.id] = item.image_storage_urls
            }
        } catch {
            print("ArchiveManager: Failed bulk R2 URL fetch natively: \(error)")
            return
        }

        for modelID in resourceIDs {
            guard let record = self.modelContext.model(for: modelID) as? LocalScanRecord else { continue }
            let scanId = targetMappings[modelID] ?? record.id
            
            let remoteUrls = remoteUrlMap[scanId] ?? []
            guard let firstString = remoteUrls.first, let remoteUrl = URL(string: firstString) else {
                record.isLocallyArchived = true
                continue
            }
            
            do {
                // Crucially stream the binary directly to a local disk tempURL entirely bypassing RAM
                let (tempURL, response) = try await URLSession.shared.download(from: remoteUrl)
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    continue
                }
                
                let filename = UUID().uuidString + ".jpg"
                let fileURL = documentsDirectory.appendingPathComponent(filename)
                
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
                
                record.localImagePath = filename
                record.isLocallyArchived = true
                
                print("ArchiveManager: Successfully rescued scan \(record.id) off the R2 edge.")
            } catch {
                print("ArchiveManager: Failed to rescue aging boundary payload - \(error.localizedDescription)")
            }
        }
        
        do {
            try self.modelContext.save()
        } catch {
            print("ArchiveManager: Failed to persist ASP contextual state: \(error.localizedDescription)")
        }
    }
}
