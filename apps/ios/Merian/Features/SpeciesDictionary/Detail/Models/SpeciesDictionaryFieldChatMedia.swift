import Foundation

enum SpeciesDictionaryFieldChatMedia {
    static func images(for subjectID: String, species: SpeciesDictionaryEntry?) -> [FieldChatMedia] {
        guard let species,
              SpeciesDictionaryChatPresentationPolicy.canonicalSpeciesID(species.id) == subjectID else { return [] }
        return images(species.referenceImages)
    }

    static func images(_ images: [SpeciesDictionaryReferenceImage]) -> [FieldChatMedia] {
        FieldChatMedia.orderedUnique(images.compactMap { image in
            .image(
                path: image.url, label: "Species reference image",
                attribution: image.fullscreenAttributionLabel
            )
        })
    }
}
