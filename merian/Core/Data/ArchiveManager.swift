import Foundation
import Photos
import SwiftUI

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
}
