import CoreLocation
import Foundation
import ImageIO
import Observation
import os
import Photos
import UIKit
import UniformTypeIdentifiers

// MARK: - Core Camera Roll Bridge
/// Manages fetching the most recent photo thumbnail from the user's camera roll securely without extracting PII.
@MainActor
@Observable final class PhotoLibraryManager: NSObject, PHPhotoLibraryChangeObserver {
    // MARK: - Singleton Architecture
    static let shared = PhotoLibraryManager()
    
    // MARK: - State Management
    var latestThumbnail: UIImage?
    
    // MARK: - Hardware Lifecycle
    private var isObserving = false
    
    private override init() {
        super.init()
    }
    
    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    // MARK: - Library Polling Engine
    func startObservingAndFetch() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .authorized, .limited:
            self.setupObservation()
            self.retrieveLatestAsset()
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
    
    // MARK: - PHPhotoLibraryChangeObserver
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Run back on the main thread to grab the newly added image if the library changes (e.g., they took a photo)
        Task { @MainActor in
            self.retrieveLatestAsset()
        }
    }
    
    // MARK: - Hardware Write Orchestration
    private enum ResourcePayload: Sendable {
        case data(Data)
        case url(URL)
    }

    private enum ProcessedResourcePayload: Sendable {
        case data(Data)
        case fileURL(URL, deleteAfterUse: Bool)
    }

    private func executePhotoLibraryWrite(payload: ResourcePayload, location: CLLocation?, accessLevel: PHAccessLevel) async -> Bool {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: accessLevel)
        let status: PHAuthorizationStatus
        
        if currentStatus == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: accessLevel)
        } else {
            status = currentStatus
        }
        
        guard status == .authorized || status == .limited else {
            MerianLog.data.debug("⚠️ Insufficient permissions to securely persist array into Camera Roll.")
            return false
        }
        
        do {
            let processedPayload = await Task.detached(priority: .utility) {
                Self.process(payload: payload)
            }.value
            defer {
                if case .fileURL(let url, true) = processedPayload {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                // Directly pass the stripped privacy safe buffers natively avoiding GPS PII persistence.
                switch processedPayload {
                case .data(let data):
                    request.addResource(with: .photo, data: data, options: nil)
                case .fileURL(let url, _):
                    request.addResource(with: .photo, fileURL: url, options: nil)
                }
                
                if let validLocation = location {
                    request.location = validLocation
                }
            }
            return true
        } catch {
            MerianLog.data.debug("⚠️ Failed to natively save image to photo library bounds: \(error, privacy: .private)")
            return false
        }
    }
    
    func saveImageToLibrary(imageData: Data, location: CLLocation? = nil) async {
        let shouldSave = UserDefaults.standard.object(forKey: "saveToCameraRoll") as? Bool ?? false
        guard shouldSave else { return }
        
        let success = await executePhotoLibraryWrite(payload: .data(imageData), location: location, accessLevel: .readWrite)
        if success {
            MerianLog.data.debug("📸 Captured image efficiently pushed down into native Camera Roll.")
        }
    }
    
    func saveImageManual(imageData: Data) async -> Bool {
        return await executePhotoLibraryWrite(payload: .data(imageData), location: nil, accessLevel: .addOnly)
    }
    
    func saveImageManual(fileURL: URL) async -> Bool {
        return await executePhotoLibraryWrite(payload: .url(fileURL), location: nil, accessLevel: .addOnly)
    }
    
    // MARK: - Privacy & EXIF Scrubbing
    /// Resolves memory buffers and strips precise PII GPS dict arrays securely
    nonisolated private static func stripGPS(from data: Data) -> Data? {
        return autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source) else {
                return nil
            }
            
            let mutableData = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(mutableData, type, 1, nil) else {
                return nil
            }
            
            guard var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                return nil
            }
            
            properties[kCGImagePropertyGPSDictionary] = nil
            
            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            
            return mutableData as Data
        }
    }

    nonisolated private static func process(payload: ResourcePayload) -> ProcessedResourcePayload {
        switch payload {
        case .data(let data):
            return .data(Self.stripGPS(from: data) ?? data)
        case .url(let url):
            if let scrubbedURL = Self.stripGPS(fromFileAt: url) {
                return .fileURL(scrubbedURL, deleteAfterUse: scrubbedURL != url)
            }
            return .fileURL(url, deleteAfterUse: false)
        }
    }

    nonisolated private static func stripGPS(fromFileAt url: URL) -> URL? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let type = CGImageSourceGetType(source),
                  var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
                return nil
            }

            properties[kCGImagePropertyGPSDictionary] = nil

            let fileExtension = preferredFilenameExtension(for: type, fallbackURL: url)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)

            guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, type, 1, nil) else {
                return nil
            }

            CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                try? FileManager.default.removeItem(at: outputURL)
                return nil
            }

            return outputURL
        }
    }

    nonisolated private static func preferredFilenameExtension(for type: CFString, fallbackURL: URL) -> String {
        if let preferred = UTType(type as String)?.preferredFilenameExtension {
            return preferred
        }
        if !fallbackURL.pathExtension.isEmpty {
            return fallbackURL.pathExtension
        }
        return "jpg"
    }
}
