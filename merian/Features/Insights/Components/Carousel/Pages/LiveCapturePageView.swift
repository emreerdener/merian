import SwiftUI

// MARK: - Live Capture Page
let liveCaptureCache: NSCache<NSNumber, UIImage> = {
    let c = NSCache<NSNumber, UIImage>()
    c.totalCostLimit = 50 * 1024 * 1024  // 50 MB
    c.countLimit = 5
    return c
}()

/// Executes downsampling directly on layout evaluation. Modern A-Series silicon resolves 
/// the ImageIO downsample significantly fast enough to guarantee the Carousel
/// launches synchronously pre-mounted with the photo, completely eradicating transient black frames.
struct LiveCapturePageView: View {
    let data: Data
    
    private var instantImage: UIImage? {
        let key = NSNumber(value: data.hashValue)
        if let cached = liveCaptureCache.object(forKey: key) {
            return cached
        }
        
        // Force synchronous decode natively
        let img = autoreleasepool { () -> UIImage? in
            if let cgImage = ImageDownsampler.downsample(data: data, maxSize: 2048) {
                return UIImage(cgImage: cgImage)
            }
            return nil
        }
        
        if let img {
            let cost = Int(img.size.width * img.size.height * 4)
            liveCaptureCache.setObject(img, forKey: key, cost: cost)
        }
        return img
    }

    var body: some View {
        Group {
            if let img = instantImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}
