import Foundation
import os

extension InferenceSpeciesHydrationCoordinator.Dependencies {
    static let live = Self(
        logWikipediaResponse: { imageURL in
            MerianLog.general.debug(
                "Wikipedia hydration returned imageUrl: \(imageURL ?? "nil", privacy: .private)"
            )
        },
        logWikipediaApplied: { urls in
            MerianLog.general.debug(
                "Wiki hydration applied. New state: \(urls, privacy: .public)"
            )
        },
        logGBIFResponse: { urls in
            MerianLog.general.debug(
                "GBIF hydration returned \(urls.count, privacy: .public) usable URLs: \(urls, privacy: .private)"
            )
        },
        logFailure: { scope, error in
            switch scope {
            case .wikipedia:
                MerianLog.general.debug(
                    "Wikipedia hydration skipped: \(error, privacy: .private)"
                )
            case .gbif:
                MerianLog.general.debug(
                    "GBIF image hydration skipped: \(error, privacy: .private)"
                )
            case .metadata:
                MerianLog.general.debug(
                    "Enrichment scope failed: \(error, privacy: .private)"
                )
            case .lookalikes:
                MerianLog.general.debug(
                    "Lookalikes scope failed: \(error, privacy: .private)"
                )
            }
        }
    )
}
