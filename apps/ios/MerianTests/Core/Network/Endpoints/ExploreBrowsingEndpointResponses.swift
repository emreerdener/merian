/// Synthetic wire fixtures; never captured public profiles, media, or locations.
enum ExploreBrowsingEndpointResponses {
    static let post = """
    {"post_id":"post","scan_id":"scan","hero_image_url":"https://media.example.test/image.webp",
     "shared_at":"2026-01-01T12:00:00.000Z","author_user_id":"author","author_name":"Test observer",
     "author_username":"test_observer","author_avatar_url":null,"author_is_pro":true,
     "species_common_name":"Test bird","species_scientific_name":"Avis test",
     "hashtags":["test"],"public_location_label":null,"location_sharing":"private",
     "time_of_day":"day","current_month":1,"weather_condition":"Clear","weather_temperature_f":74,
     "like_count":11,"comment_count":2,"viewer_has_liked":false,"is_owned_by_viewer":false,"ranking_value":4}
    """

    static let unrankedPost = """
    {"post_id":"audio-post","scan_id":"audio-scan","hero_image_url":null,
     "reference_thumbnail_url":"https://media.example.test/reference.webp",
     "shared_at":"2026-01-01T11:00:00.000Z","author_user_id":"author","author_name":"Test observer",
     "species_common_name":"Test bird","species_scientific_name":"Avis test","location_sharing":"obscured",
     "like_count":4,"comment_count":1,"viewer_has_liked":true,"is_owned_by_viewer":false,"ranking_value":null,
     "media_items":[{"kind":"audio","url":"https://media.example.test/audio.wav",
      "thumbnail_url":"https://media.example.test/spectrogram.webp","order_index":0,
      "duration_seconds":4.2,"has_audio":true}]}
    """

    static let feed = #"{"data":[\#(post)]}"#
    static let singlePost = #"{"data":\#(post)}"#
    static let authorPosts = """
    {"data":[\(post)],"next_cursor":{
     "before_shared_at":"2026-01-01T12:00:00.000Z","before_post_id":"post"}}
    """
    static let speciesPosts = """
    {"data":[\(unrankedPost)],"next_cursor":{
     "image_quality_score":null,"shared_at":"2026-01-01T11:00:00.000Z","post_id":"audio-post"}}
    """

    static let profile = """
    {"data":{"author_user_id":"author","author_name":"Test observer","author_username":"test_observer",
     "author_avatar_url":"https://media.example.test/avatar.webp","author_is_pro":true,
     "species_count":12,"current_streak":4,"published_post_count":5,"follower_count":7,"following_count":3,
     "viewer_is_following":false,"viewer_can_report":false,
     "owner_publication_summary":{"publication_intent_count":38,"visible_post_count":5,
      "recovery_needed_post_count":33,"degraded_post_count":0,"quarantined_post_count":33},
     "heatmap":{"total_captures":17,"current_month_captures":3,"year_string":"2026",
      "weeks":[{"month_label":"Jan","days":[{"count":1,"date":"2026-01-01T00:00:00Z"},
       {"count":0,"date":"2026-01-02T00:00:00Z"}]}]},
     "awards":[{"type":"explorer","current_count":5,"last_interaction_at":"2026-01-01T12:00:00.000Z"},
      {"type":"first_field_trip","current_count":1,"last_interaction_at":"2026-01-01T11:00:00.000Z"}],
     "preview_posts":[\(post)]}}
    """

    static let publicProfile = """
    {"data":{"author_user_id":"author","author_name":"Test observer","species_count":0,"current_streak":0,
     "published_post_count":0,"follower_count":0,"following_count":0,"viewer_is_following":false,
     "viewer_can_report":true,"heatmap":{"total_captures":0,"current_month_captures":0,"year_string":"2026",
     "weeks":[]},"awards":[],"preview_posts":[]}}
    """

    // Out-of-range sentinels exercise transport mapping without storing coordinates.
    static let map = """
    {"mode":"posts","visible_count":1,"category_counts":[{"category":"birds","count":1}],
     "media_type_counts":[{"media_type":"image","count":4},{"media_type":"audio","count":2}],
     "clusters":[],"posts":[{"post_id":"map-post","scan_id":"scan","latitude":1234.5,"longitude":-6789.5,
      "coordinate_visibility":"obscured","shared_at":"2026-01-01T12:00:00.000Z",
      "author_user_id":"author","author_name":"Test observer","species_common_name":"Test bird",
      "species_scientific_name":"Avis test","like_count":2,"comment_count":1,"viewer_has_liked":true,
      "is_owned_by_viewer":false,"reference_thumbnail_url":"https://media.example.test/reference.webp",
      "media_items":[{"kind":"audio","url":"https://media.example.test/audio.wav","thumbnail_url":null,
       "order_index":0,"duration_seconds":4.2,"has_audio":true}]}]}
    """

    static let clusters = """
    {"mode":"clusters","visible_count":7,"clusters":[
     {"id":"cluster","latitude":1234.5,"longitude":-6789.5,"post_count":7}],"posts":[]}
    """

    static let detail = """
    {"schema_version":1,"data":{"post_id":"post","field_notes":"Test field notes",
     "location_sharing":"private","map_point":null,"hashtags":["test"],"species_dictionary_id":"species",
     "alternative_common_names":["Test bird"],"taxonomy_kingdom":"Animalia","taxonomy_phylum":"Chordata",
     "taxonomy_class":"Aves","taxonomy_order":"Test order","taxonomy_family":"Test family",
     "taxonomy_genus":"Avis","ai_reasoning":"Test reasoning","habitat_description":"Test habitat",
     "gbif_taxon_key":3000001,"iucn_red_list_status":"LC","hazard_type":"none",
     "wikipedia_url":"https://reference.example.test/bird","reference_image_url":"https://media.example.test/bird.webp",
     "wikipedia_overview":"Test overview","similar_species":[]}}
    """
}
