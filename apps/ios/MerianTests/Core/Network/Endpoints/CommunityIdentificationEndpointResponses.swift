/// Synthetic wire fixtures; no live responses, account data, or observed locations.
enum CommunityIdentificationEndpointResponses {
    static let feed = #"""
    {"data":[{
        "request_id":"request","post_id":"post","scan_id":"scan",
        "hero_image_url":"https://media.example.test/community.webp",
        "requested_at":"2026-01-01T12:00:00.000Z",
        "author_user_id":"author","author_name":"Test observer",
        "author_username":"test_observer","author_is_pro":true,
        "taxonomy_version_id":"taxonomy-version",
        "projection_state":"community_needs_id","consensus_processing_state":"idle",
        "current_taxon_id":"taxon","current_common_name":"Test rose",
        "current_scientific_name":"Rosa test","current_rank":"species",
        "current_path":"plantae.rosa.rosa_test","initial_taxon_id":"initial-taxon",
        "initial_common_name":"Initial rose","initial_scientific_name":"Rosa initial",
        "initial_rank":"species","initial_path":"plantae.rosa.rosa_initial",
        "request_group":"plants","consensus_score":0.5,
        "identification_count":2,"viewer_has_identified":false,
        "public_location_label":"Test region","location_sharing":"open",
        "media_items":[{
            "kind":"image","url":"https://media.example.test/community.webp",
            "thumbnail_url":"https://media.example.test/community-thumb.webp",
            "order_index":0,"duration_seconds":null,"has_audio":false
        }]
    }]}
    """#

    static let activity = #"""
    {"data":[{
        "activity_id":"activity","activity_type":"suggestion_burst",
        "request_id":"request","post_id":"post","scan_id":"scan",
        "hero_image_url":"https://media.example.test/community.webp",
        "activity_at":"2026-01-01T12:00:00.000Z","suggestion_count":3,
        "recent_actor_names":["test_observer","test_contributor"],
        "taxon_id":"taxon","taxon_common_name":"Test rose",
        "taxon_scientific_name":"Rosa test","taxon_rank":"species",
        "consensus_score":0.82,"request_group":"plants",
        "media_items":[{
            "kind":"image","url":"https://media.example.test/community.webp",
            "thumbnail_url":"https://media.example.test/community-thumb.webp",
            "order_index":0,"duration_seconds":null,"has_audio":false
        }]
    },{
        "activity_id":"consensus","activity_type":"consensus_changed",
        "request_id":"request","post_id":"post","scan_id":"scan",
        "hero_image_url":null,"activity_at":"2026-01-01T11:00:00Z",
        "suggestion_count":0,"recent_actor_names":[],"media_items":[]
    },{
        "activity_id":"resolved","activity_type":"resolved",
        "request_id":"request","post_id":"post","scan_id":"scan",
        "activity_at":"2026-01-01T10:00:00Z",
        "suggestion_count":0,"recent_actor_names":[],"media_items":[]
    }]}
    """#

    static let detail = #"""
    {"data":{
        "request_id":"request","post_id":"post","scan_id":"scan",
        "hero_image_url":"https://media.example.test/community.webp",
        "requested_at":"2026-01-01T12:00:00.000Z","status":"needs_id",
        "note":"Test request","author_user_id":"author","author_name":"Test observer",
        "taxonomy_version_id":"taxonomy-version","consensus_processing_state":"queued",
        "identification_count":1,"viewer_identification_id":"identification",
        "location_sharing":"obscured","inference_tier":"pro",
        "suggested_taxa":[{
            "taxon_id":"taxon","taxonomy_version_id":"taxonomy-version",
            "scientific_name":"Rosa test","rank":"species","path":"plantae.rosa.rosa_test",
            "species_id":null,"suggestion_source":"ai_initial","confidence_score":0.8,
            "distinguishing_feature":"Test reasoning"
        }],
        "identifications":[{
            "id":"identification","user_id":"contributor","author_name":"Test contributor",
            "taxon_id":"taxon","taxonomy_version_id":"taxonomy-version",
            "scientific_name":"Rosa test","rank":"species",
            "disagreement_mode":"implicit_support","role_label":"supporting",
            "is_genus_best_possible":false,"reasoning":null,
            "created_at":"2026-01-01T12:01:00.000Z","withdrawn_at":null,"is_viewer":true
        }]
    }}
    """#

    static let taxa = #"""
    {"data":[{
        "taxon_id":"taxon","taxonomy_version_id":"taxonomy-version",
        "common_name":null,"scientific_name":"Rosa test","rank":"species",
        "path":"plantae.rosa.rosa_test","species_id":null,
        "gbif_taxon_key":3000001,"source":"gbif","is_in_dictionary":false,
        "accepted_gbif_taxon_key":3000001,"taxonomic_status":"accepted"
    }]}
    """#

    static let update = #"""
    {"success":true,"data":{
        "id":"request","post_id":"post","note":"Test request",
        "location_sharing":"obscured","updated_at":"2026-01-01T12:01:00.000Z"
    }}
    """#

    static let submittedMutation = #"""
    {"success":true,"data":{
        "id":"identification","request_id":"request","post_id":"post",
        "user_id":"contributor","taxon_node_id":"taxon",
        "disagreement_mode":"explicit_disagreement","is_genus_best_possible":true,
        "reasoning":"Test reasoning","created_at":"2026-01-01T12:01:00.000Z",
        "withdrawn_at":null,"restored_at":null
    }}
    """#

    static let withdrawnMutation = #"""
    {"success":true,"data":{
        "id":"identification","request_id":"request","post_id":"post",
        "user_id":"contributor","taxon_node_id":"taxon",
        "disagreement_mode":"explicit_disagreement","is_genus_best_possible":true,
        "reasoning":"Test reasoning","created_at":"2026-01-01T12:01:00.000Z",
        "withdrawn_at":"2026-01-01T12:02:00.000Z","restored_at":null
    }}
    """#

    static let restoredMutation = #"""
    {"success":true,"data":{
        "id":"identification","request_id":"request","post_id":"post",
        "user_id":"contributor","taxon_node_id":"taxon",
        "disagreement_mode":"explicit_disagreement","is_genus_best_possible":true,
        "reasoning":"Test reasoning","created_at":"2026-01-01T12:01:00.000Z",
        "withdrawn_at":null,"restored_at":"2026-01-01T12:03:00.000Z"
    }}
    """#
}
