import Foundation

extension InferenceHydrationPersistenceService {
    static let live = InferenceHydrationPersistenceService(
        dependencies: Dependencies(
            persistReference: { snapshot, modelContainer in
                let database = BackgroundDatabaseActor(
                    modelContainer: modelContainer
                )
                await database.updateScanWithWikipedia(
                    scanId: snapshot.scanId,
                    extract: snapshot.extract,
                    url: snapshot.url,
                    imageUrl: snapshot.imageUrl,
                    expectedScientificName: snapshot.expectedScientificName
                )
            },
            persistMetadata: { snapshot, modelContainer in
                let database = BackgroundDatabaseActor(
                    modelContainer: modelContainer
                )
                await database.updateScanWithEnrichment(
                    scanId: snapshot.scanId,
                    habitatDescription: snapshot.habitatDescription,
                    gbifTaxonKey: snapshot.gbifTaxonKey,
                    similarSpeciesJsonData: nil,
                    taxonomy: snapshot.taxonomy,
                    alternativeCommonNames:
                        snapshot.alternativeCommonNames,
                    expectedScientificName:
                        snapshot.expectedScientificName
                )
            },
            persistLookalikes: { snapshot, modelContainer in
                let entries = snapshot.entries
                let encodedLookalikes: Data? = await Task.detached(
                    priority: .utility
                ) {
                    try? JSONEncoder().encode(entries)
                }.value
                let database = BackgroundDatabaseActor(
                    modelContainer: modelContainer
                )
                await database.updateScanWithEnrichment(
                    scanId: snapshot.scanId,
                    habitatDescription: nil,
                    gbifTaxonKey: nil,
                    similarSpeciesJsonData: encodedLookalikes,
                    taxonomy: nil,
                    expectedScientificName:
                        snapshot.expectedScientificName
                )
            }
        )
    )
}
