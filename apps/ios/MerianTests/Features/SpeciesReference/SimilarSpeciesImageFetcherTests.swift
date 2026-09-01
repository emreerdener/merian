import Foundation
import Testing
import UIKit

@testable import Merian

@MainActor
struct SimilarSpeciesImageFetcherTests {
    @Test func successfulLoadPublishesImagesAndFallbackName() async {
        let expectedImage = UIImage()
        var requestedNames: [String] = []
        let fetcher = SimilarSpeciesImageFetcher(
            dependencies: .init { scientificName in
                requestedNames.append(scientificName)
                return SimilarSpeciesImageLoadOutput(
                    images: [expectedImage],
                    commonName: "Monarch butterfly"
                )
            }
        )

        let didLoad = await fetcher.fetchImage(
            for: "Danaus plexippus"
        )

        #expect(didLoad)
        #expect(requestedNames == ["Danaus plexippus"])
        #expect(fetcher.images.count == 1)
        #expect(fetcher.images.first === expectedImage)
        #expect(fetcher.commonName == "Monarch butterfly")
        #expect(!fetcher.isLoading)
    }

    @Test func emptyOutputRestoresIdleState() async {
        let fetcher = SimilarSpeciesImageFetcher(
            dependencies: .init { _ in
                SimilarSpeciesImageLoadOutput(
                    images: [],
                    commonName: nil
                )
            }
        )

        let didLoad = await fetcher.fetchImage(
            for: "Danaus plexippus"
        )

        #expect(!didLoad)
        #expect(fetcher.images.isEmpty)
        #expect(!fetcher.isLoading)
    }

    @Test func lateImageLoadCannotOverwriteNewSpecies() async {
        let staleImage = UIImage()
        let currentImage = UIImage()
        var pendingFirstLoad: CheckedContinuation<
            SimilarSpeciesImageLoadOutput,
            Never
        >?
        let fetcher = SimilarSpeciesImageFetcher(
            dependencies: .init { scientificName in
                if scientificName == "Danaus plexippus" {
                    return await withCheckedContinuation {
                        pendingFirstLoad = $0
                    }
                }
                return SimilarSpeciesImageLoadOutput(
                    images: [currentImage],
                    commonName: "Queen"
                )
            }
        )

        let firstLoad = Task {
            await fetcher.fetchImage(for: "Danaus plexippus")
        }
        while pendingFirstLoad == nil {
            await Task.yield()
        }

        let secondDidLoad = await fetcher.fetchImage(
            for: "Danaus gilippus"
        )
        pendingFirstLoad?.resume(
            returning: SimilarSpeciesImageLoadOutput(
                images: [staleImage],
                commonName: "Monarch"
            )
        )
        let firstDidLoad = await firstLoad.value

        #expect(secondDidLoad)
        #expect(!firstDidLoad)
        #expect(fetcher.images.first === currentImage)
        #expect(fetcher.commonName == "Queen")
        #expect(!fetcher.isLoading)
    }

    @Test func emptyIdentityInvalidatesAnInFlightImageLoad() async {
        let staleImage = UIImage()
        var pendingLoad: CheckedContinuation<
            SimilarSpeciesImageLoadOutput,
            Never
        >?
        let fetcher = SimilarSpeciesImageFetcher(
            dependencies: .init { _ in
                await withCheckedContinuation {
                    pendingLoad = $0
                }
            }
        )

        let firstLoad = Task {
            await fetcher.fetchImage(for: "Danaus plexippus")
        }
        while pendingLoad == nil {
            await Task.yield()
        }

        let emptyDidLoad = await fetcher.fetchImage(for: "")
        pendingLoad?.resume(
            returning: SimilarSpeciesImageLoadOutput(
                images: [staleImage],
                commonName: "Monarch"
            )
        )
        let firstDidLoad = await firstLoad.value

        #expect(!emptyDidLoad)
        #expect(!firstDidLoad)
        #expect(fetcher.images.isEmpty)
        #expect(fetcher.commonName == nil)
        #expect(!fetcher.isLoading)
    }

    @Test func preCancelledLoadDoesNotClaimGenerationOwnership() async {
        let expectedImage = UIImage()
        var requestedNames: [String] = []
        let fetcher = SimilarSpeciesImageFetcher(
            dependencies: .init { scientificName in
                requestedNames.append(scientificName)
                return SimilarSpeciesImageLoadOutput(
                    images: [expectedImage],
                    commonName: "Monarch butterfly"
                )
            }
        )

        _ = await fetcher.fetchImage(for: "Danaus plexippus")
        let cancelledLoad = Task {
            await fetcher.fetchImage(for: "Danaus gilippus")
        }
        cancelledLoad.cancel()
        let didLoad = await cancelledLoad.value

        #expect(!didLoad)
        #expect(requestedNames == ["Danaus plexippus"])
        #expect(fetcher.images.first === expectedImage)
        #expect(fetcher.commonName == "Monarch butterfly")
        #expect(!fetcher.isLoading)
    }

    @Test func downloadsAreRestoredToCandidateOrder() {
        let completionOrder: [(index: Int, value: String?)] = [
            (index: 2, value: "third"),
            (index: 0, value: "first"),
            (index: 1, value: nil)
        ]

        #expect(
            SimilarSpeciesImageService.orderedLoadedValues(
                from: completionOrder
            ) == ["first", "third"]
        )
    }

    @Test func endpointAdaptersPreserveWikipediaAndGBIFContracts() throws {
        let wikipedia = try #require(
            SimilarSpeciesImageService.wikipediaRequest(
                scientificName: "Danaus plexippus"
            )
        )
        let gbif = try #require(
            SimilarSpeciesImageService.gbifRequest(
                scientificName: "Danaus plexippus"
            )
        )
        let gbifURL = try #require(gbif.url)
        let gbifComponents = try #require(
            URLComponents(
                url: gbifURL,
                resolvingAgainstBaseURL: false
            )
        )
        let query: [String: String] = Dictionary(
            uniqueKeysWithValues: (gbifComponents.queryItems ?? []).compactMap {
                item in item.value.map { (item.name, $0) }
            }
        )

        #expect(
            wikipedia.url?.absoluteString ==
                "https://en.wikipedia.org/api/rest_v1/page/summary/Danaus_plexippus"
        )
        #expect(
            wikipedia.value(forHTTPHeaderField: "User-Agent") == "Merian/1.0"
        )
        #expect(gbifComponents.scheme == "https")
        #expect(gbifComponents.host == "api.gbif.org")
        #expect(gbifComponents.path == "/v1/occurrence/search")
        #expect(query["scientificName"] == "Danaus plexippus")
        #expect(query["mediaType"] == "StillImage")
        #expect(query["limit"] == "5")
    }
}
