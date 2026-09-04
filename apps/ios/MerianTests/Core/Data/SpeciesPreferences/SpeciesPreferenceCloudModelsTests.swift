import Foundation
@testable import Merian
import Testing

@Suite("Species Preference Cloud Models")
struct SpeciesPreferenceCloudModelsTests {
    @Test func cloudRowDecodesTheExistingPostgRESTShape() throws {
        let data = Data(
            """
            {
              "scientific_name": "Quercus macrocarpa",
              "preferred_common_name": "Bur Oak",
              "updated_at": "2026-08-01T12:34:56.000Z",
              "deleted_at": null
            }
            """.utf8
        )

        let row = try JSONDecoder().decode(
            SpeciesPreferenceCloudRow.self,
            from: data
        )

        #expect(row.scientific_name == "Quercus macrocarpa")
        #expect(row.preferred_common_name == "Bur Oak")
        #expect(row.updated_at == "2026-08-01T12:34:56.000Z")
        #expect(row.deleted_at == nil)
    }

    @Test func tombstoneUpsertEncodesExplicitNullsAndExistingKeys() throws {
        let upsert = SpeciesPreferenceCloudUpsert(
            user_id: "11111111-1111-1111-1111-111111111111",
            scientific_name: "Quercus macrocarpa",
            preferred_common_name: nil,
            deleted_at: "2026-08-01T12:34:56.000Z"
        )

        let object = try #require(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(upsert)
            ) as? [String: Any]
        )

        #expect(
            object["user_id"] as? String
                == "11111111-1111-1111-1111-111111111111"
        )
        #expect(
            object["scientific_name"] as? String
                == "Quercus macrocarpa"
        )
        #expect(object["preferred_common_name"] is NSNull)
        #expect(
            object["deleted_at"] as? String
                == "2026-08-01T12:34:56.000Z"
        )
    }
}
