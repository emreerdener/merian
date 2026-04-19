import Foundation

let subjectFunnels: [String: [GuidedQuestion]] = [
    "subj_bird": [
        GuidedQuestion(
            prompt: "What type of bird was it?",
            tags: [
                .init(tagId: "bird_type_song", label: "Songbird", aiText: "a songbird", defaultWeight: 40),
                .init(tagId: "bird_type_prey", label: "Bird of prey", aiText: "a bird of prey", defaultWeight: 30),
                .init(tagId: "bird_type_wade", label: "Wading bird", aiText: "a wading bird", defaultWeight: 20),
                .init(tagId: "bird_type_water", label: "Waterfowl", aiText: "a waterfowl", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "About how large was the bird?",
            tags: [
                .init(tagId: "bird_size_spar", label: "Sparrow-sized", aiText: "sparrow-sized", defaultWeight: 40),
                .init(tagId: "bird_size_pig", label: "Pigeon-sized", aiText: "pigeon-sized", defaultWeight: 30),
                .init(tagId: "bird_size_crow", label: "Crow-sized", aiText: "crow-sized", defaultWeight: 20),
                .init(tagId: "bird_size_eagl", label: "Eagle-sized", aiText: "eagle-sized", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "How would you describe its beak?",
            tags: [
                .init(tagId: "bird_beak_short", label: "Short & thick", aiText: "with a short, thick beak", defaultWeight: 40),
                .init(tagId: "bird_beak_long", label: "Long & curved", aiText: "with a long, curved beak", defaultWeight: 30),
                .init(tagId: "bird_beak_hook", label: "Hooked", aiText: "with a hooked beak", defaultWeight: 20),
                .init(tagId: "bird_beak_thin", label: "Straight & thin", aiText: "with a straight, thin beak", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What did its feathers look like?",
            tags: [
                .init(tagId: "bird_plum_brown", label: "Brown/streaked", aiText: "with brown or streaked plumage", defaultWeight: 40),
                .init(tagId: "bird_plum_bw", label: "Black & white", aiText: "with black and white plumage", defaultWeight: 30),
                .init(tagId: "bird_plum_vivid", label: "Vivid colors", aiText: "with vivid colors", defaultWeight: 20),
                .init(tagId: "bird_plum_grey", label: "Grey/blue", aiText: "with grey or blue plumage", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What behavior did you observe?",
            tags: [
                .init(tagId: "bird_behav_forage", label: "Foraging ground", aiText: "foraging on the ground", defaultWeight: 40),
                .init(tagId: "bird_behav_perch", label: "Perching canopy", aiText: "perching in the canopy", defaultWeight: 30),
                .init(tagId: "bird_behav_water", label: "Near water", aiText: "near the water", defaultWeight: 20),
                .init(tagId: "bird_behav_flight", label: "In flight", aiText: "in flight", defaultWeight: 10)
            ]
        )
    ],
    "subj_insec": [
        GuidedQuestion(
            prompt: "What type of insect did you find?",
            tags: [
                .init(tagId: "ins_kind_beetle", label: "Beetle", aiText: "a beetle", defaultWeight: 50),
                .init(tagId: "ins_kind_butterfly", label: "Butterfly or moth", aiText: "a butterfly or moth", defaultWeight: 40),
                .init(tagId: "ins_kind_bee", label: "Bee or wasp", aiText: "a bee or wasp", defaultWeight: 30),
                .init(tagId: "ins_kind_fly", label: "Fly", aiText: "a fly", defaultWeight: 20),
                .init(tagId: "ins_kind_dragon", label: "Dragonfly", aiText: "a dragonfly", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Did you notice its wings?",
            tags: [
                .init(tagId: "ins_wing_fold", label: "Wings folded/hidden", aiText: "with wings folded or hidden", defaultWeight: 30),
                .init(tagId: "ins_wing_rest", label: "Wings visible at rest", aiText: "with wings visible at rest", defaultWeight: 20),
                .init(tagId: "ins_wing_fly", label: "Flying", aiText: "flying", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "How would you describe its body texture?",
            tags: [
                .init(tagId: "ins_body_hard", label: "Hard shiny shell", aiText: "with a hard shiny shell", defaultWeight: 40),
                .init(tagId: "ins_body_fuzzy", label: "Fuzzy or hairy", aiText: "fuzzy or hairy", defaultWeight: 30),
                .init(tagId: "ins_body_waist", label: "Slender waist", aiText: "with a slender waist", defaultWeight: 20),
                .init(tagId: "ins_body_flat", label: "Flattened", aiText: "with a flattened body", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Did you notice any distinct colors or markings?",
            tags: [
                .init(tagId: "ins_mark_dark", label: "Black or dark", aiText: "black or dark colored", defaultWeight: 40),
                .init(tagId: "ins_mark_warn", label: "Bright warning colors", aiText: "with bright warning colors", defaultWeight: 30),
                .init(tagId: "ins_mark_camo", label: "Camouflaged", aiText: "camouflaged", defaultWeight: 20),
                .init(tagId: "ins_mark_metal", label: "Metallic", aiText: "with a metallic shine", defaultWeight: 10)
            ]
        )
    ],
    "subj_plan": [
        GuidedQuestion(
            prompt: "What kind of plant is it?",
            tags: [
                .init(tagId: "pln_kind_tree", label: "Tree", aiText: "a tree", defaultWeight: 50),
                .init(tagId: "pln_kind_shrub", label: "Shrub or bush", aiText: "a shrub or bush", defaultWeight: 40),
                .init(tagId: "pln_kind_flower", label: "Flowering plant", aiText: "a flowering plant", defaultWeight: 30),
                .init(tagId: "pln_kind_fern", label: "Fern or moss", aiText: "a fern or moss", defaultWeight: 20),
                .init(tagId: "pln_kind_grass", label: "Grass", aiText: "grass", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Was it in bloom or showing any fruit?",
            tags: [
                .init(tagId: "pln_rep_bloom", label: "In bloom", aiText: "in bloom", defaultWeight: 30),
                .init(tagId: "pln_rep_seed", label: "Seed pods or fruit", aiText: "with seed pods or fruit", defaultWeight: 20),
                .init(tagId: "pln_rep_leaves", label: "Leaves only", aiText: "showing leaves only", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "How would you describe its leaves?",
            tags: [
                .init(tagId: "pln_leaf_broad", label: "Broad & flat", aiText: "with broad and flat leaves", defaultWeight: 40),
                .init(tagId: "pln_leaf_needle", label: "Needle-like", aiText: "with needle-like leaves", defaultWeight: 30),
                .init(tagId: "pln_leaf_comp", label: "Compound leaflets", aiText: "with compound leaflets", defaultWeight: 20),
                .init(tagId: "pln_leaf_waxy", label: "Waxy or succulent", aiText: "with waxy or succulent leaves", defaultWeight: 10)
            ]
        )
    ],
    "subj_spid": [
        GuidedQuestion(
            prompt: "What type of spider was it?",
            tags: [
                .init(tagId: "spd_kind_web", label: "Web-building spider", aiText: "a web-building spider", defaultWeight: 40),
                .init(tagId: "spd_kind_hunt", label: "Hunting spider", aiText: "a hunting spider", defaultWeight: 30),
                .init(tagId: "spd_kind_taran", label: "Tarantula or similar", aiText: "a tarantula or large hairy spider", defaultWeight: 20),
                .init(tagId: "spd_kind_tick", label: "Tick or mite", aiText: "a tick or mite", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "About how big was it?",
            tags: [
                .init(tagId: "spd_size_tiny", label: "Tiny", aiText: "tiny", defaultWeight: 40),
                .init(tagId: "spd_size_pea", label: "Pea-sized", aiText: "pea-sized", defaultWeight: 30),
                .init(tagId: "spd_size_coin", label: "Coin-sized", aiText: "coin-sized", defaultWeight: 20),
                .init(tagId: "spd_size_palm", label: "Palm-sized", aiText: "palm-sized", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Did you notice any distinct colors or markings?",
            tags: [
                .init(tagId: "spd_col_brown", label: "Brown/grey", aiText: "brown or grey", defaultWeight: 40),
                .init(tagId: "spd_col_bright", label: "Brightly colored", aiText: "brightly colored", defaultWeight: 30),
                .init(tagId: "spd_col_dark", label: "Dark/black", aiText: "dark or black", defaultWeight: 20),
                .init(tagId: "spd_col_stripe", label: "Striped/patterned", aiText: "striped or patterned", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Was there a web nearby?",
            tags: [
                .init(tagId: "spd_web_orb", label: "Orb web", aiText: "in a circular orb web", defaultWeight: 40),
                .init(tagId: "spd_web_messy", label: "Messy cobweb", aiText: "in a messy cobweb", defaultWeight: 30),
                .init(tagId: "spd_web_funnel", label: "Funnel web", aiText: "in a funnel web", defaultWeight: 20),
                .init(tagId: "spd_web_none", label: "No web", aiText: "without a web", defaultWeight: 10)
            ]
        )
    ],
    "subj_rept": [
        GuidedQuestion(
            prompt: "What type of reptile or amphibian was it?",
            tags: [
                .init(tagId: "rep_kind_snake", label: "Snake", aiText: "a snake", defaultWeight: 40),
                .init(tagId: "rep_kind_lizard", label: "Lizard", aiText: "a lizard", defaultWeight: 30),
                .init(tagId: "rep_kind_turtle", label: "Turtle or tortoise", aiText: "a turtle or tortoise", defaultWeight: 20),
                .init(tagId: "rep_kind_frog", label: "Frog or toad", aiText: "a frog or toad", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "How would you describe its skin texture?",
            tags: [
                .init(tagId: "rep_skin_smooth", label: "Smooth scales", aiText: "with smooth scales", defaultWeight: 40),
                .init(tagId: "rep_skin_rough", label: "Rough or spiky", aiText: "with rough or spiky scales", defaultWeight: 30),
                .init(tagId: "rep_skin_moist", label: "Moist and smooth", aiText: "with moist and smooth skin", defaultWeight: 20),
                .init(tagId: "rep_skin_shell", label: "Shell or carapace", aiText: "with a shell or carapace", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Did it have any noticeable patterns?",
            tags: [
                .init(tagId: "rep_pat_solid", label: "Solid color", aiText: "a solid single color", defaultWeight: 40),
                .init(tagId: "rep_pat_stripe", label: "Striped", aiText: "striped", defaultWeight: 30),
                .init(tagId: "rep_pat_spot", label: "Spotted or mottled", aiText: "spotted or mottled", defaultWeight: 20),
                .init(tagId: "rep_pat_band", label: "Banded", aiText: "banded", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Where exactly was it resting or found?",
            tags: [
                .init(tagId: "rep_loc_ground", label: "On the ground", aiText: "on the ground", defaultWeight: 40),
                .init(tagId: "rep_loc_tree", label: "In trees or bushes", aiText: "in trees or bushes", defaultWeight: 30),
                .init(tagId: "rep_loc_water", label: "Near or in water", aiText: "near or in water", defaultWeight: 20),
                .init(tagId: "rep_loc_rock", label: "Under a rock", aiText: "under a rock", defaultWeight: 10)
            ]
        )
    ],
    "subj_mush": [
        GuidedQuestion(
            prompt: "What was the mushroom's overall shape?",
            tags: [
                .init(tagId: "msh_shape_classic", label: "Classic cap & stem", aiText: "with a classic cap and stem", defaultWeight: 40),
                .init(tagId: "msh_shape_bracket", label: "Bracket or shelf", aiText: "growing as a bracket or shelf", defaultWeight: 30),
                .init(tagId: "msh_shape_puff", label: "Puffball", aiText: "shaped like a puffball", defaultWeight: 20),
                .init(tagId: "msh_shape_coral", label: "Coral or cup-shaped", aiText: "coral or cup-shaped", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "How would you describe the top of the cap?",
            tags: [
                .init(tagId: "msh_cap_smooth", label: "Smooth", aiText: "with a smooth cap", defaultWeight: 40),
                .init(tagId: "msh_cap_scaly", label: "Scaly", aiText: "with a scaly cap", defaultWeight: 30),
                .init(tagId: "msh_cap_slimy", label: "Slimy or sticky", aiText: "with a slimy or sticky cap", defaultWeight: 20),
                .init(tagId: "msh_cap_velvet", label: "Hairy or velvety", aiText: "with a hairy or velvety cap", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What did the underside look like?",
            tags: [
                .init(tagId: "msh_under_gills", label: "Gills", aiText: "with gills underneath", defaultWeight: 40),
                .init(tagId: "msh_under_pores", label: "Pores", aiText: "with pores underneath", defaultWeight: 30),
                .init(tagId: "msh_under_teeth", label: "Teeth or spines", aiText: "with teeth or spines underneath", defaultWeight: 20),
                .init(tagId: "msh_under_smooth", label: "Smooth", aiText: "smooth underneath", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What was it growing out of?",
            tags: [
                .init(tagId: "msh_grow_soil", label: "Soil", aiText: "growing in soil", defaultWeight: 40),
                .init(tagId: "msh_grow_dead", label: "Dead wood", aiText: "growing on dead wood", defaultWeight: 30),
                .init(tagId: "msh_grow_tree", label: "Living tree", aiText: "growing on a living tree", defaultWeight: 20),
                .init(tagId: "msh_grow_grass", label: "Grass", aiText: "growing in grass", defaultWeight: 10)
            ]
        )
    ],
    "subj_mamm": [
        GuidedQuestion(
            prompt: "What kind of mammal did you spot?",
            tags: [
                .init(tagId: "mam_kind_rodent", label: "Rodent", aiText: "a rodent", defaultWeight: 40),
                .init(tagId: "mam_kind_squirrel", label: "Squirrel", aiText: "a squirrel", defaultWeight: 30),
                .init(tagId: "mam_kind_rabbit", label: "Rabbit or hare", aiText: "a rabbit or hare", defaultWeight: 20),
                .init(tagId: "mam_kind_raccoon", label: "Raccoon/skunk/opossum", aiText: "a raccoon, skunk, or opossum", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What did its tail look like?",
            tags: [
                .init(tagId: "mam_tail_bushy", label: "Long and bushy", aiText: "with a long, bushy tail", defaultWeight: 40),
                .init(tagId: "mam_tail_thin", label: "Long and thin", aiText: "with a long, thin tail", defaultWeight: 30),
                .init(tagId: "mam_tail_short", label: "Short or hidden", aiText: "with a short or hidden tail", defaultWeight: 20),
                .init(tagId: "mam_tail_prehen", label: "Prehensile", aiText: "with a prehensile tail", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What color was its fur?",
            tags: [
                .init(tagId: "mam_fur_brown", label: "Brown or tan", aiText: "with brown or tan fur", defaultWeight: 40),
                .init(tagId: "mam_fur_grey", label: "Grey", aiText: "with grey fur", defaultWeight: 30),
                .init(tagId: "mam_fur_bw", label: "Black and white", aiText: "with black and white fur", defaultWeight: 20),
                .init(tagId: "mam_fur_red", label: "Reddish", aiText: "with reddish fur", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What time of day was it active?",
            tags: [
                .init(tagId: "mam_time_day", label: "Daytime", aiText: "active during the day", defaultWeight: 40),
                .init(tagId: "mam_time_dusk", label: "Dusk or dawn", aiText: "active at dusk or dawn", defaultWeight: 30),
                .init(tagId: "mam_time_night", label: "Nighttime", aiText: "active at night", defaultWeight: 20)
            ]
        )
    ],
    "subj_fish": [
        GuidedQuestion(
            prompt: "How would you describe its body shape?",
            tags: [
                .init(tagId: "fsh_shape_torp", label: "Torpedo-like", aiText: "with a torpedo-like body", defaultWeight: 40),
                .init(tagId: "fsh_shape_deep", label: "Deep-bodied/flat", aiText: "deep-bodied or flat", defaultWeight: 30),
                .init(tagId: "fsh_shape_eel", label: "Eel-like", aiText: "with an eel-like body", defaultWeight: 20),
                .init(tagId: "fsh_shape_bottom", label: "Bottom-dweller", aiText: "shaped like a bottom-dweller", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "What type of water environment was it in?",
            tags: [
                .init(tagId: "fsh_water_stream", label: "Freshwater stream", aiText: "in a freshwater stream", defaultWeight: 40),
                .init(tagId: "fsh_water_lake", label: "Lake or pond", aiText: "in a lake or pond", defaultWeight: 30),
                .init(tagId: "fsh_water_reef", label: "Saltwater reef", aiText: "in a saltwater reef", defaultWeight: 20),
                .init(tagId: "fsh_water_ocean", label: "Open ocean", aiText: "in the open ocean", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Did it have any distinct colors?",
            tags: [
                .init(tagId: "fsh_col_silver", label: "Silvery", aiText: "silvery-colored", defaultWeight: 40),
                .init(tagId: "fsh_col_bright", label: "Brightly colored", aiText: "brightly colored", defaultWeight: 30),
                .init(tagId: "fsh_col_camo", label: "Camouflaged/dull", aiText: "camouflaged or dull-colored", defaultWeight: 20),
                .init(tagId: "fsh_col_stripe", label: "Striped", aiText: "striped", defaultWeight: 10)
            ]
        ),
        GuidedQuestion(
            prompt: "Did you notice anything unique about its fins?",
            tags: [
                .init(tagId: "fsh_fin_spike", label: "Spiky dorsal fin", aiText: "with a spiky dorsal fin", defaultWeight: 40),
                .init(tagId: "fsh_fin_flow", label: "Large flowing fins", aiText: "with large flowing fins", defaultWeight: 30),
                .init(tagId: "fsh_fin_fork", label: "Forked tail", aiText: "with a forked tail", defaultWeight: 20),
                .init(tagId: "fsh_fin_round", label: "Rounded tail", aiText: "with a rounded tail", defaultWeight: 10)
            ]
        )
    ],
    "subj_othr": [
        guidedQuestions[3], // Size
        guidedQuestions[4], // Shape
        guidedQuestions[5], // Details
        guidedQuestions[6], // Colors
        guidedQuestions[7], // Action
        guidedQuestions[8]  // Social
    ]
]
