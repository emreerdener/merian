import AVFoundation
import SwiftUI
import UIKit

struct ExploreCoverVideoPlayer: UIViewRepresentable {
    let player: AVPlayer
    let playerId: String
    let surface: ExploreVideoPlaybackSurface

    func makeUIView(context: Context) -> ExplorePlayerLayerView {
        let view = ExplorePlayerLayerView()
        view.playerLayer.player = player
        MerianLog.exploreVideo.debug(
            "layer attach player=\(self.playerId, privacy: .public) surface=\(self.surface.rawValue, privacy: .public)"
        )
        return view
    }

    func updateUIView(_ view: ExplorePlayerLayerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
            MerianLog.exploreVideo.debug(
                "layer update player=\(self.playerId, privacy: .public) surface=\(self.surface.rawValue, privacy: .public)"
            )
        }
        view.playerLayer.videoGravity = .resizeAspectFill
    }

    static func dismantleUIView(_ view: ExplorePlayerLayerView, coordinator: ()) {
        MerianLog.exploreVideo.debug("layer dismantle")
        view.playerLayer.player = nil
    }
}
final class ExplorePlayerLayerView: UIView {
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        backgroundColor = .black
        clipsToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
