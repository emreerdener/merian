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
        let fileManager = FileManager.default
        let path = NSHomeDirectory()
        if let attributes = try? fileManager.attributesOfFileSystem(forPath: path),
           let freeSize = attributes[.systemFreeSize] as? Int64 {
            return freeSize
        }
        return 0
    }
    
    private func downloadToLocalLibrary(url: URL) async throws {
        var remoteData: Data? = nil
        if !url.isFileURL {
            let (downloadedData, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            remoteData = downloadedData
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            if url.isFileURL {
                creationRequest.addResource(with: .photo, fileURL: url, options: nil)
            } else if let data = remoteData {
                creationRequest.addResource(with: .photo, data: data, options: nil)
            }
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
                let backgroundContext = ModelContext(container)
                
                guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                
                for modelID in resourceIDs {
                    guard let record = backgroundContext.model(for: modelID) as? LocalScanRecord else { continue }
                    
                    // Natively query the Supabase edge to extract the physical R2 url
                    struct ScanUrlResponse: Decodable {
                        let image_storage_urls: [String]
                    }
                    
                    let remoteUrl: URL
                    do {
                        let postgrestResponse = try await SupabaseManager.shared.client
                            .from("scans")
                            .select("image_storage_urls")
                            .eq("id", value: record.id)
                            .single()
                            .execute()
                        
                        let decoder = JSONDecoder()
                        let parsed = try decoder.decode(ScanUrlResponse.self, from: postgrestResponse.data)
                        
                        guard let firstString = parsed.image_storage_urls.first,
                              let parsedUrl = URL(string: firstString) else {
                            // Mark structurally synced if no cloud URLs remain bounds-wise
                            record.isLocallyArchived = true
                            continue
                        }
                        
                        remoteUrl = parsedUrl
                    } catch {
                        print("ArchiveManager: Failed to fetch remote URL for scan \(record.id)")
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
                    try backgroundContext.save()
                } catch {
                    print("ArchiveManager: Failed to persist ASP contextual state: \(error.localizedDescription)")
                }
            }
        } catch {
            print("ArchiveManager: Failed to evaluate offline sweeps bounds: \(error.localizedDescription)")
        }
    }
}
