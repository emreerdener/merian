import Foundation

enum RemoteImageRetryPolicy {
    static let maximumAttempts = 3

    static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 ||
            statusCode == 425 ||
            statusCode == 429 ||
            (500...599).contains(statusCode)
    }

    static func shouldRetry(urlErrorCode: URLError.Code) -> Bool {
        switch urlErrorCode {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .resourceUnavailable,
             .cannotLoadFromNetwork,
             .secureConnectionFailed,
             .badServerResponse,
             .zeroByteResource,
             .backgroundSessionWasDisconnected:
            return true
        default:
            // A reconnect changes the SwiftUI task identity and retries
            // .notConnectedToInternet without spinning while fully offline.
            return false
        }
    }

    static func delayMilliseconds(afterAttempt attempt: Int) -> Int {
        switch attempt {
        case 1: return 250
        default: return 750
        }
    }
}
