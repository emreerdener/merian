import AVFoundation

enum VideoPlaybackAvailability: Equatable {
    case loading
    case ready
    case unavailable

    init(itemStatus: AVPlayerItem.Status) {
        switch itemStatus {
        case .unknown:
            self = .loading
        case .readyToPlay:
            self = .ready
        case .failed:
            self = .unavailable
        @unknown default:
            self = .unavailable
        }
    }
}
