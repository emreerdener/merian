import Foundation
import Testing

@testable import Merian

private actor SpeciesReferenceRequestRecorder {
    private var requests: [URLRequest] = []

    func record(_ request: URLRequest) {
        requests.append(request)
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }
}

@Suite("Species Reference Hydration Service")
struct SpeciesReferenceHydrationServiceTests {
    @Test func wikipediaBuildsExpectedRequestAndParsesDescription() async throws {
        let recorder = SpeciesReferenceRequestRecorder()
        let data = Data(
            #"""
            {
              "lead": {
                "normalizedtitle": "Danaus plexippus",
                "originalimage": {
                  "source": "https://upload.wikimedia.org/monarch.jpg"
                }
              },
              "remaining": {
                "sections": [
                  {
                    "title": "Description",
                    "anchor": "Description",
                    "text": "<p>Orange &amp; black</p><p>White spots</p>"
                  }
                ]
              }
            }
            """#.utf8
        )
        let service = SpeciesReferenceHydrationService { request in
            await recorder.record(request)
            return (
                data,
                try #require(HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.invalid")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
            )
        }

        let reference = try #require(
            try await service.fetchWikipediaReference(
                for: "Danaus plexippus"
            )
        )

        #expect(reference.overview == "Orange & black\nWhite spots")
        #expect(
            reference.pageURL ==
                "https://en.wikipedia.org/wiki/Danaus_plexippus"
        )
        #expect(
            reference.imageURL ==
                "https://upload.wikimedia.org/monarch.jpg"
        )

        let request = try #require(await recorder.lastRequest())
        #expect(
            request.url?.absoluteString ==
                "https://en.wikipedia.org/api/rest_v1/page/mobile-sections/Danaus_plexippus"
        )
        #expect(request.timeoutInterval == 8)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Merian/1.0")
    }

    @Test func wikipediaRetainsMediaWhenDescriptionIsUnavailable() async throws {
        let data = Data(
            #"""
            {
              "lead": {
                "normalizedtitle": "Danaus plexippus",
                "originalimage": {
                  "source": "https://upload.wikimedia.org/monarch.jpg"
                }
              },
              "remaining": {
                "sections": [
                  { "title": "Taxonomy", "text": "<p>Nymphalidae</p>" }
                ]
              }
            }
            """#.utf8
        )
        let service = SpeciesReferenceHydrationService { request in
            (
                data,
                try #require(HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.invalid")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
            )
        }

        let reference = try #require(
            try await service.fetchWikipediaReference(
                for: "Danaus plexippus"
            )
        )

        #expect(reference.overview == nil)
        #expect(
            reference.pageURL ==
                "https://en.wikipedia.org/wiki/Danaus_plexippus"
        )
        #expect(
            reference.imageURL ==
                "https://upload.wikimedia.org/monarch.jpg"
        )
    }

    @Test func gbifUsesFirstStillImageFromEachOccurrence() async throws {
        let recorder = SpeciesReferenceRequestRecorder()
        let data = Data(
            #"""
            {
              "results": [
                {
                  "media": [
                    { "type": "Sound", "identifier": "https://example.com/audio" },
                    { "type": "StillImage", "identifier": "https://example.com/one.jpg" },
                    { "type": "StillImage", "identifier": "https://example.com/ignored.jpg" }
                  ]
                },
                {
                  "media": [
                    { "type": "StillImage", "identifier": "https://example.com/two.jpg" }
                  ]
                }
              ]
            }
            """#.utf8
        )
        let service = SpeciesReferenceHydrationService { request in
            await recorder.record(request)
            return (
                data,
                try #require(HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.invalid")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ))
            )
        }

        let urls = try await service.fetchGBIFImageURLs(taxonKey: 5_131_904)

        #expect(
            urls == [
                "https://example.com/one.jpg",
                "https://example.com/two.jpg"
            ]
        )
        let request = try #require(await recorder.lastRequest())
        #expect(
            request.url?.absoluteString ==
                "https://api.gbif.org/v1/occurrence/search?taxonKey=5131904&mediaType=StillImage&limit=4"
        )
        #expect(request.timeoutInterval == 10)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == nil)
    }

    @Test func unsuccessfulResponsesProduceNoHydration() async throws {
        let service = SpeciesReferenceHydrationService { request in
            (
                Data("{}".utf8),
                try #require(HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.invalid")!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: nil
                ))
            )
        }

        #expect(
            try await service.fetchWikipediaReference(for: "Missing species") == nil
        )
        #expect(try await service.fetchGBIFImageURLs(taxonKey: 1).isEmpty)
    }
}
