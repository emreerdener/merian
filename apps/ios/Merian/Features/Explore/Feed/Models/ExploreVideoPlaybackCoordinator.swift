import Observation
import SwiftUI

enum ExploreVideoPlaybackSurface: String {
    case feed
    case detail
    case communityIdentification
}

@MainActor
@Observable
final class ExploreVideoPlaybackCoordinator {
    struct OverlayToken: Hashable {
        fileprivate let id: UUID
        let reason: String

        init(id: UUID = UUID(), reason: String) {
            self.id = id
            self.reason = reason
        }
    }

    private(set) var activePlayerID: String?
    private(set) var overlayDepth = 0
    private(set) var pauseGeneration: UInt64 = 0
    private(set) var resumeGeneration: UInt64 = 0

    private var overlayReasonsByToken: [OverlayToken: String] = [:]

    var hasActiveOverlay: Bool {
        overlayDepth > 0
    }

    func activate(playerID: String, surface: ExploreVideoPlaybackSurface) {
        guard activePlayerID != playerID else { return }

        activePlayerID = playerID
        MerianLog.exploreVideo.debug(
            "active player=\(playerID, privacy: .public) surface=\(surface.rawValue, privacy: .public)"
        )
    }

    func clearActivePlayer(_ playerID: String) {
        guard activePlayerID == playerID else { return }

        activePlayerID = nil
        MerianLog.exploreVideo.debug("cleared active player=\(playerID, privacy: .public)")
    }

    func beginOverlay(reason: String) -> OverlayToken {
        let token = OverlayToken(reason: reason)
        overlayReasonsByToken[token] = reason
        overlayDepth = overlayReasonsByToken.count
        pauseGeneration &+= 1

        MerianLog.exploreVideo.debug(
            "overlay began reason=\(reason, privacy: .public) depth=\(self.overlayDepth, privacy: .public) pauseGeneration=\(self.pauseGeneration, privacy: .public)"
        )

        return token
    }

    func endOverlay(_ token: OverlayToken) {
        guard let reason = overlayReasonsByToken.removeValue(forKey: token) else {
            MerianLog.exploreVideo.debug(
                "ignored duplicate overlay end reason=\(token.reason, privacy: .public) depth=\(self.overlayDepth, privacy: .public)"
            )
            return
        }

        overlayDepth = overlayReasonsByToken.count

        if overlayDepth == 0 {
            resumeGeneration &+= 1
            MerianLog.exploreVideo.debug(
                "overlay ended reason=\(reason, privacy: .public) depth=0 resumeGeneration=\(self.resumeGeneration, privacy: .public)"
            )
        } else {
            MerianLog.exploreVideo.debug(
                "overlay ended reason=\(reason, privacy: .public) depth=\(self.overlayDepth, privacy: .public)"
            )
        }
    }
}

private struct ExploreVideoOverlayLifecycleModifier: ViewModifier {
    let isPresented: Bool
    let reason: String

    @Environment(ExploreVideoPlaybackCoordinator.self) private var coordinator: ExploreVideoPlaybackCoordinator?
    @State private var overlayToken: ExploreVideoPlaybackCoordinator.OverlayToken?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented, initial: true) { _, newValue in
                reconcileOverlayState(isPresented: newValue)
            }
            .onDisappear {
                endOverlayIfNeeded()
            }
    }

    private func reconcileOverlayState(isPresented: Bool) {
        if isPresented {
            beginOverlayIfNeeded()
        } else {
            endOverlayIfNeeded()
        }
    }

    private func beginOverlayIfNeeded() {
        guard overlayToken == nil,
              let coordinator else { return }

        overlayToken = coordinator.beginOverlay(reason: reason)
    }

    private func endOverlayIfNeeded() {
        guard let token = overlayToken else { return }

        overlayToken = nil
        coordinator?.endOverlay(token)
    }
}

extension View {
    func exploreVideoOverlayLifecycle(isPresented: Bool, reason: String) -> some View {
        modifier(ExploreVideoOverlayLifecycleModifier(isPresented: isPresented, reason: reason))
    }
}
