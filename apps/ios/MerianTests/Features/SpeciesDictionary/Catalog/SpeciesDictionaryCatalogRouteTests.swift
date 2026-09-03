import Foundation
import Testing

@testable import Merian

@Suite("Species Dictionary Catalog Routes")
struct SpeciesDictionaryCatalogRouteTests {
    @Test func catalogItemRoutesToDictionaryCatalog() {
        let item = SpeciesDictionaryCatalogItem(
            id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            contentQuality: .complete,
            taxonomy: nil,
            iucnRedListStatus: nil,
            hazardType: nil,
            groupTags: [],
            referenceImageUrl: nil
        )

        #expect(item.dictionaryRoute.entryPoint == .exploreDictionaryCatalog)
        #expect(item.dictionaryRoute.speciesId == item.id)
        #expect(item.dictionaryRoute.scientificName == item.scientificName)
    }

    @Test func featuredSpeciesRoutesToDictionaryCatalog() {
        let item = SpeciesDictionaryFeaturedSpecies(
            id: "1cf79982-e5ee-4e3d-8d65-274527e6ae01",
            scientificName: "Danaus plexippus",
            commonName: "Monarch Butterfly",
            overview: nil,
            referenceImageUrl: nil
        )

        #expect(item.dictionaryRoute.speciesId == "1cf79982-e5ee-4e3d-8d65-274527e6ae01")
        #expect(item.dictionaryRoute.entryPoint == .exploreDictionaryCatalog)
        #expect(item.dictionaryRoute.scientificName == item.scientificName)
    }
}
