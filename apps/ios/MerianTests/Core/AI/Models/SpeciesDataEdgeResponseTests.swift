import Foundation
@testable import Merian
import Testing

struct SpeciesDataEdgeResponseTests {
    @Test(arguments: ["flash", "pro"])
    func audioConfidencePresentationUsesResolvedIdentity(tier: String) throws {
        let strong = InferenceConfidencePolicy.bands(forInferenceTier: tier).strong
        let cases: [(biological: Bool, common: String, scientific: String?, score: Double, style: ConfidenceBadgePresentation.Style)] = [
            (true, "American Robin", "Turdus migratorius", strong, .strong),
            (true, "American Robin", "Turdus migratorius", strong - 0.0001, .possible),
            (true, "Unidentified Wildlife", nil, 1, .unknown),
            (true, "Human", "Homo sapiens", 1, .strong),
            (false, "No Wildlife Detected", nil, 1, .unknown)
        ]
        for item in cases {
            var data: [String: Any] = [
                "is_biological_subject": item.biological,
                "common_name": item.common,
                "confidence_score": item.score,
                "inference_tier": tier
            ]
            if let name = item.scientific { data["scientific_name"] = name }
            let encoded = try JSONSerialization.data(withJSONObject: ["success": true, "data": data])
            let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: encoded)
            let species = SpeciesData(
                fromEdgeResponse: wrapper.data,
                locationName: nil,
                weatherCondition: nil,
                weatherTemperatureF: nil
            )
            let badge = ConfidenceBadgePresentation.resolve(
                confidenceScore: species.presentationConfidenceScore,
                inferenceTier: species.inferenceTier,
                hasUserOverride: false,
                isUserConfirmed: false,
                analyzingPhrase: nil
            )
            #expect(species.confidenceScore == item.score)
            #expect(badge.style == item.style)
            #expect(badge.isVisible == (item.style != .unknown))
            #expect(!species.userConfirmedIdentification)
        }
    }

    @Test func edgeResponseMapsNewToMerianDictionaryFlag() throws {
        let json = Data("""
        {
          "success": true,
          "data": {
            "scan_id": "scan_new_dictionary",
            "is_biological_subject": true,
            "is_live_capture": true,
            "scientific_name": "Danaus plexippus",
            "common_name": "Monarch Butterfly",
            "confidence_score": 0.97,
            "ecology_type": "wild",
            "is_new_to_merian_dictionary": true,
            "insight_data": {
              "ai_reasoning": "Orange wings with black veins.",
              "hazard_type": "none"
            }
          }
        }
        """.utf8)

        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.isNewToMerianDictionary == true)
        #expect(species.isNewDiscovery == false)
    }

    @Test func edgeResponseDefaultsNewToMerianDictionaryFlagToFalse() throws {
        let json = Data("""
        {
          "success": true,
          "data": {
            "scan_id": "scan_cached_dictionary",
            "is_biological_subject": true,
            "is_live_capture": true,
            "scientific_name": "Danaus plexippus",
            "common_name": "Monarch Butterfly",
            "confidence_score": 0.97,
            "ecology_type": "wild",
            "alternative_common_names": null,
            "insight_data": {
              "ai_reasoning": "Orange wings with black veins.",
              "hazard_type": "none"
            }
          }
        }
        """.utf8)

        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.isNewToMerianDictionary == false)
        #expect(species.alternativeCommonNames == nil)
    }

    @Test func nonBiologicalEdgeResponseIgnoresDictionaryMilestoneFlag() throws {
        let json = Data("""
        {
          "success": true,
          "data": {
            "scan_id": "scan_nonbio_dictionary_flag",
            "is_biological_subject": false,
            "is_live_capture": false,
            "scientific_name": "Ovis aries",
            "common_name": "Wool Kilim Rug",
            "confidence_score": 0.82,
            "is_new_to_merian_dictionary": true,
            "insight_data": {
              "ai_reasoning": "The subject is an inanimate textile.",
              "hazard_type": "none"
            }
          }
        }
        """.utf8)

        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.isBiological == false)
        #expect(species.isNewToMerianDictionary == false)
    }

    @Test func humanAudioMapsAsResolvedBiologicalSubjectWithoutCandidates() throws {
        let json = Data("""
        {
          "success": true,
          "data": {
            "scan_id": "human_audio",
            "is_biological_subject": true,
            "is_live_capture": true,
            "scientific_name": "Homo sapiens",
            "common_name": "Human",
            "confidence_score": 0.99,
            "candidates": [
              {
                "scientific_name": "Turdus migratorius",
                "confidence_score": 0.72
              }
            ],
            "insight_data": {
              "ai_reasoning": "The recording contains human breathing.",
              "hazard_type": "none"
            }
          }
        }
        """.utf8)

        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        var species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )
        species.audioFilePaths = ["human.wav"]

        #expect(species.isBiological)
        #expect(species.isHumanSubject)
        #expect(species.hasResolvedBiologicalIdentification)
        #expect(species.commonName == "Human")
        #expect(species.scientificName == "Homo sapiens")
        #expect(species.presentationConfidenceScore == 0.99)
        #expect(species.candidates == nil)
        #expect(species.shouldSuppressReferenceImages)
    }

    @Test func malformedHistoricalHumanAliasKeepsHumanSafeguards() throws {
        let json = Data("""
        {
          "success": true,
          "data": {
            "scan_id": "legacy_human_audio",
            "is_biological_subject": true,
            "is_live_capture": true,
            "scientific_name": "Homo sapien",
            "common_name": "Unknown Subject",
            "confidence_score": 0.99,
            "candidates": [
              {
                "scientific_name": "Turdus migratorius",
                "confidence_score": 0.72
              }
            ],
            "insight_data": {
              "ai_reasoning": "Legacy structured output.",
              "hazard_type": "none"
            }
          }
        }
        """.utf8)

        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.isHumanSubject)
        #expect(species.subjectDisplayName(isAudioOnlyObservation: true) == "Human")
        #expect(species.presentationScientificName == "Homo sapiens")
        #expect(species.candidates == nil)
        #expect(species.shouldSuppressReferenceImages)
    }

    @Test func unresolvedAudioUsesWildlifePresentationAndSuppressesMatchConfidence() throws {
        let json = Data("""
        {
          "success": true,
          "data": {
            "scan_id": "unresolved_audio",
            "is_biological_subject": true,
            "is_live_capture": true,
            "common_name": "Unidentified Wildlife",
            "confidence_score": 0.98,
            "candidates": [
              {
                "scientific_name": "Hyla cinerea",
                "confidence_score": 0.64
              }
            ],
            "insight_data": {
              "ai_reasoning": "A non-human animal call is present but unresolved.",
              "hazard_type": "none"
            }
          }
        }
        """.utf8)

        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        var species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )
        species.audioFilePaths = ["wildlife.wav"]

        #expect(species.isUnresolvedBiologicalSubject)
        #expect(!species.hasResolvedBiologicalIdentification)
        #expect(
            species.subjectDisplayName(isAudioOnlyObservation: true) ==
                "Unidentified Wildlife"
        )
        #expect(species.presentationConfidenceScore == nil)
        #expect(species.candidates == nil)
        #expect(!species.isNewToMerianDictionary)
        #expect(species.shouldSuppressReferenceImages)
    }

    @Test(arguments: ["", " \n\t "])
    func testBlankHabitatRemainsMissingAcrossDomainInitializers(
        habitat: String
    ) throws {
        let species = SpeciesData(
            commonName: "Firefly",
            scientificName: "Photinus pyralis",
            insightData: InsightData(
                aiReasoning: "Synthetic observation.",
                hazardType: "none"
            ),
            confidenceScore: 0.95,
            habitatDescription: habitat
        )
        #expect(species.habitatDescription == nil)

        let responseData = try JSONSerialization.data(withJSONObject: [
            "success": true,
            "data": [
                "is_biological_subject": true,
                "common_name": "Firefly",
                "scientific_name": "Photinus pyralis",
                "confidence_score": 0.95,
                "species_insights": ["habitat_description": habitat]
            ]
        ])
        let response = try JSONDecoder().decode(
            EdgeResponseWrapper.self,
            from: responseData
        )
        let decodedSpecies = SpeciesData(
            fromEdgeResponse: response.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )
        #expect(decodedSpecies.habitatDescription == nil)
    }

    @Test func testAIScientificNameSetFromEdgeResponseInit() throws {
        let json = Data("""
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.98,
                "insight_data": {
                    "ai_reasoning": "A butterfly.",
                    "hazard_type": "none"
                }
            }
        }
        """.utf8)
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.aiScientificName == "Danaus plexippus")
        #expect(species.userIdentificationOverride == nil)
        #expect(species.userConfirmedIdentification == false)
        #expect(species.isFlagged == false)
    }

    @Test func testCandidatesMappedFromEdgeResponse() throws {
        let json = Data("""
        {
            "success": true,
            "data": {
                "scan_id": "candidates_spec_scan",
                "is_biological_subject": true,
                "scientific_name": "Procyon lotor",
                "common_name": "Raccoon",
                "confidence_score": 0.78,
                "insight_data": {
                    "ai_reasoning": "A procyonid.",
                    "hazard_type": "none"
                },
                "candidates": [
                    {
                        "scientific_name": "Procyon cancrivorus",
                        "confidence_score": 0.71
                    },
                    {
                        "scientific_name": "Bassariscus astutus",
                        "confidence_score": 0.65
                    }
                ]
            }
        }
        """.utf8)
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        let candidates = try #require(species.candidates)
        #expect(candidates.count == 2)
        #expect(candidates[0].scientificName == "Procyon cancrivorus")
        #expect(candidates[0].confidenceScore == 0.71)
    }

    @Test func testNilCandidatesOnHighConfidenceEdgeResponse() throws {
        let json = Data("""
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "scientific_name": "Danaus plexippus",
                "common_name": "Monarch Butterfly",
                "confidence_score": 0.97,
                "insight_data": {
                    "ai_reasoning": "Distinctive wings.",
                    "hazard_type": "none"
                }
            }
        }
        """.utf8)
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.candidates == nil)
    }

    @Test func testNonBiologicalEdgeResponseIgnoresCandidates() throws {
        let json = Data("""
        {
            "success": true,
            "data": {
                "is_biological_subject": false,
                "is_live_capture": false,
                "scientific_name": "Ovis aries",
                "common_name": "Wool Kilim Rug",
                "confidence_score": 0.82,
                "insight_data": {
                    "ai_reasoning": "A processed textile.",
                    "hazard_type": "none"
                },
                "candidates": [
                    {
                        "scientific_name": "Capra hircus",
                        "confidence_score": 0.41
                    }
                ]
            }
        }
        """.utf8)
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.isBiological == false)
        #expect(species.candidates == nil)
    }

    @Test func testPetIdentificationDecodesFromEdgeResponse() throws {
        let json = Data("""
        {
            "success": true,
            "data": {
                "is_biological_subject": true,
                "scientific_name": "Canis lupus familiaris",
                "common_name": "Domestic Dog",
                "confidence_score": 0.94,
                "insight_data": {
                    "ai_reasoning": "A domestic dog.",
                    "hazard_type": "none"
                },
                "pet_identification": {
                    "species_group": "dog",
                    "label": "Australian Cattle Dog",
                    "label_type": "breed",
                    "confidence_score": 0.91,
                    "evidence": ["blue roan coat", "compact build"]
                }
            }
        }
        """.utf8)
        let wrapper = try JSONDecoder().decode(EdgeResponseWrapper.self, from: json)
        let species = SpeciesData(
            fromEdgeResponse: wrapper.data,
            locationName: nil,
            weatherCondition: nil,
            weatherTemperatureF: nil
        )

        #expect(species.commonName == "Domestic Dog")
        #expect(species.scientificName == "Canis lupus familiaris")
        #expect(species.petIdentification?.label == "Australian Cattle Dog")
        #expect(species.petIdentification?.confidenceScore == 0.91)
    }
}
