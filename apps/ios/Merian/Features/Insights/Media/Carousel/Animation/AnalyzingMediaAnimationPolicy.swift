import Foundation
import SwiftUI

enum StillImageAnalyzingMode: Equatable {
    case fullImageScan
    case isolatedFocus(NormalizedImageFocusRegion)

    init(focusRegion: NormalizedImageFocusRegion?) {
        if let focusRegion {
            self = .isolatedFocus(focusRegion)
        } else {
            self = .fullImageScan
        }
    }
}

/// Owns one analysis clock above the conditional media overlay. Queue-owner
/// handoffs keep the same session, while a different scan or a later analysis
/// of the same scan receives a fresh clock and continuity token.
struct AnalyzingMediaAnimationSession: Equatable {
    private(set) var scanID: String?
    private(set) var startedAt: Date
    private(set) var continuityToken: UUID
    private(set) var isProcessing: Bool

    init(
        scanID: String? = nil,
        startedAt: Date = Date(),
        continuityToken: UUID = UUID(),
        isProcessing: Bool = false
    ) {
        self.scanID = FocusInteractionIdentity.canonicalScanID(scanID)
        self.startedAt = startedAt
        self.continuityToken = continuityToken
        self.isProcessing = isProcessing
    }

    mutating func update(
        scanID: String?,
        isProcessing: Bool,
        at date: Date = Date()
    ) {
        let canonicalScanID = FocusInteractionIdentity.canonicalScanID(scanID)
        let startedNewAnalysis = !self.isProcessing && isProcessing
        if canonicalScanID != self.scanID || startedNewAnalysis {
            startedAt = date
            continuityToken = UUID()
        }
        self.scanID = canonicalScanID
        self.isProcessing = isProcessing
    }
}

/// Derives motion from time so a retained session can recover after its render
/// transaction is interrupted by carousel updates or scene transitions.
enum AnalyzingMediaAnimationClock {
    static func sweepProgress(
        at date: Date,
        startedAt: Date,
        legDuration: TimeInterval,
        reduceMotion: Bool
    ) -> CGFloat {
        guard !reduceMotion else { return 0.5 }
        guard legDuration.isFinite, legDuration > 0 else { return 0 }

        let elapsed = max(0, date.timeIntervalSince(startedAt))
        let cyclePosition = elapsed
            .truncatingRemainder(dividingBy: legDuration * 2) / legDuration
        let linearProgress = cyclePosition <= 1
            ? cyclePosition
            : 2 - cyclePosition
        return CGFloat(UnitCurve.easeInOut.value(at: linearProgress))
    }
}
