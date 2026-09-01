import Foundation

extension MediaPlaybackDependencies {
    static var insightLive: Self {
        Self.live.configuredForFeature(
            feedbackNamespace: "media.insight"
        ) { event, gainBand in
            AppTelemetry.trackInsightAudioBoost(
                event: event,
                gainBand: gainBand
            )
        }
    }
}
