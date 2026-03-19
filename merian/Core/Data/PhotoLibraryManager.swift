import Foundation
import Photos
import UIKit

/// Manages fetching the most recent photo thumbnail from the user's camera roll securely without extracting PII.
@MainActor
final class PhotoLibraryManager: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    static let shared = PhotoLibraryManager()
    
    @Published var latestThumbnail: UIImage? = nil
    private var isObserving = false
    
    private override init() {
        super.init()
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func startObservingAndFetch() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            self.setupObservation()
            self.retrieveLatestAsset()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
                if newStatus == .authorized || newStatus == .limited {
                    Task { @MainActor in
                        self?.setupObservation()
                        self?.retrieveLatestAsset()
                    }
                }
            }
        default:
            break
        }
    }
    
    private func setupObservation() {
        guard !isObserving else { return }
        PHPhotoLibrary.shared().register(self)
        isObserving = true
    }
    
    private func retrieveLatestAsset() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 1
        
        let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        guard let latestAsset = fetchResult.firstObject else { return }
        
        let imageManager = PHImageManager.default()
        let targetSize = CGSize(width: 150, height: 150) // Small, memory-safe thumbnail size
        
        let requestOptions = PHImageRequestOptions()
        requestOptions.isNetworkAccessAllowed = true // Pull from iCloud if necessary
        requestOptions.deliveryMode = .opportunistic // Get degraded image first, then high quality
        
        imageManager.requestImage(for: latestAsset, targetSize: targetSize, contentMode: .aspectFill, options: requestOptions) { [weak self] image, _ in
            guard let image = image else { return }
            Task { @MainActor in
                self?.latestThumbnail = image
            }
        }
    }
    
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Run back on the main thread to grab the newly added image if the library changes (e.g., they took a photo)
        Task { @MainActor in
            self.retrieveLatestAsset()
        }
    }
    
    private func executePhotoLibraryWrite(imageData: Data, location: CLLocation?, accessLevel: PHAccessLevel) async -> Bool {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: accessLevel)
        let status: PHAuthorizationStatus
        
        if currentStatus == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: accessLevel)
        } else {
            status = currentStatus
        }
        
        guard status == .authorized || status == .limited else {
            print("⚠️ Insufficient permissions to securely persist array into Camera Roll.")
            return false
        }
        
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                // Directly pass the raw physics buffers seamlessly natively maintaining EXIF data dynamically.
                request.addResource(with: .photo, data: imageData, options: nil)
                
                if let validLocation = location {
                    request.location = validLocation
                }
            }
            return true
        } catch {
            print("⚠️ Failed to natively save image to photo library bounds: \(error)")
            return false
        }
    }
    
    func saveImageToLibrary(imageData: Data, location: CLLocation? = nil) async {
        let shouldSave = UserDefaults.standard.object(forKey: "saveToCameraRoll") as? Bool ?? true
        guard shouldSave else { return }
        
        let success = await executePhotoLibraryWrite(imageData: imageData, location: location, accessLevel: .readWrite)
        if success {
            print("📸 Captured image efficiently pushed down into native Camera Roll.")
        }
    }
    
    func saveImageManual(imageData: Data) async -> Bool {
        return await executePhotoLibraryWrite(imageData: imageData, location: nil, accessLevel: .addOnly)
    }
}
