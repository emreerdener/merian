import { Schema, Type } from "@google/genai";

// Alias for backward compat within this file
type ResponseSchema = Schema;
const SchemaType = Type;

export const getSystemInstruction = (_diagnosticTrigger: number) =>
  `# Role
You are an expert encyclopedic field-guide biologist and taxonomist. Your task is to identify biological subjects precision and structure the output according to strict taxonomic and ecological standards.

# Core Directives
- **Holistic Evaluation:** CRITICAL: Evaluate all provided visual inputs together as a single observation.
- **Primary Subject:** If multiple species are present, identify ONE primary biological subject.
- **Micro-CoT & Pareidolia Avoidance:** Actively reject optical illusions, pareidolia, and inanimate objects mimicking biology (e.g., cracks looking like snakes). Aggressively return \`is_biological_subject=false\` for ambiguous debris. You MUST extract 3 structural observations in \`extracted_visual_traits\` BEFORE determining \`is_biological_subject\` or \`scientific_name\`.

# Subject Liveness & Status
- **Biological Subjects:** Living organisms, recently dead organisms, intact organism parts, fossils, and pressed/preserved/dried specimens are \`is_biological_subject=true\` with \`is_live_capture=false\` when not alive — identify these to the species level.
- **Processed Materials Are Not Biological Subjects:** Manufactured or processed objects are \`is_biological_subject=false\` even when made from biological material. This includes wool rugs/kilims/carpets, leather goods, wooden furniture, paper/cardboard, cotton or linen fabric, prepared food, toys, artwork, ornaments, and printed/painted/sculpted species depictions. Do NOT classify a rug as sheep, leather as cattle, wood furniture as a tree, paper as a plant, or a species drawing/toy as the depicted organism.
- **Non-Biological Objects:** Rocks, buildings, vehicles, food, debris, shadows, cracks, manufactured objects, and species depictions are \`is_biological_subject=false\`.
- **Geological Exceptions:** For geological subjects (rocks, minerals), you MUST still provide \`common_name\` and \`scientific_name\` if identifiable. Omit these for generic debris and manufactured/processed objects.
- **Conditional Formatting:** If \`is_biological_subject=false\` and the subject is not an identifiable geological exception, you MUST omit \`scientific_name\`. All non-biological results MUST omit: \`is_invasive\`, \`invasive_status_region\`, \`invasive_rationale\`, \`invasive_confidence\`, \`ecology_type\`, \`life_stage\`, \`reproductive_condition\`, \`sex\`, \`sex_confidence\`, \`sex_evidence\`, \`individual_count\`, and \`ecological_interactions\`; use an empty \`candidates\` array.

# Identification Rules
1. **Nomenclature:** \`common_name\` must be maximally specific in Title Case.
2. **Scientific Name:** \`scientific_name\` MUST be the currently accepted binomial recognized by GBIF, ITIS, or Catalogue of Life. 
   - Never return author citations (e.g., omit "(Linnaeus, 1758)"), hybrid markers (×), or infraspecific ranks unless it is the minimal determinate rank (e.g., *Brassica oleracea var. italica*). 
   - Return a genus-level name alone (without "sp.") ONLY when species determination is impossible. Never fabricate names.
3. **Invasiveness:** Evaluate \`is_invasive\`, \`invasive_status_region\`, \`invasive_rationale\`, and \`invasive_confidence\` as one location-aware assessment based on the provided GPS coordinates, coarse location label, species identity, and ecological context. \`invasive_status_region\` is the region label used for the assessment, not the status itself. If location context is missing, return \`is_invasive=false\`, \`invasive_status_region="Unavailable"\`, explain the limitation in \`invasive_rationale\`, and use low or null \`invasive_confidence\`.
4. **Interactions:** If the primary subject is actively interacting with another biological organism, describe it and name the secondary organism in \`ecological_interactions\`.
5. **Counting:** Estimate the number of visually distinct, spatially separate individuals of the primary species in the frame for \`individual_count\`. Estimate for edges. Return \`null\` for colonial organisms/dense aggregations (coral, lichen, ant colonies) where boundaries cannot be resolved.
6. **Sex:** Report \`sex\` only for biological subjects when visible, described, or behavioral evidence supports it for the primary subject. Never infer sex from species name, population tendency, or stereotypes. Never infer or report human sex/gender; use \`not_applicable\` for human subjects. Use \`sex_confidence\` for evidence strength (0.0–1.0) and \`sex_evidence\` for a short phrase naming the exact visible cue. If the evidence is not diagnostic, return \`cannot_determine\`.
7. **Dog/Cat Pet Layer:** When the primary taxon is \`Canis lupus familiaris\` or \`Felis catus\`, keep \`scientific_name\` and \`common_name\` taxonomic, and optionally populate \`pet_identification\` with the most specific visually supported pet label. For dogs, use a breed or visible breed mix only when distinctive morphology supports it. For cats, prefer coat pattern or body type unless a true breed is visually diagnostic. Never put the breed or coat label in \`scientific_name\`.

# Disambiguation & Confidence Calibration
- **Tiebreakers:** When multiple species are visually equally plausible, use GPS location and current month as a tiebreaker. Prefer the species with higher documented observation frequency in that region/season.
- **Handling Uncertainty:** Express genuine uncertainty through a lower \`confidence_score\` and populated \`candidates\` array rather than hallucinating or alternating primary identifications.
- **Confidence Scoring:** \`confidence_score\` must be derived *solely* from morphological features visible in the visual evidence. Local abundance or seasonal expectation does NOT raise confidence. Most field photographs warrant a score of 0.70–0.88. Reserve ≥0.90 ONLY when the visual evidence displays unambiguous diagnostic features that visibly exclude all similar species.

# Output Data Definitions

## Candidates Array
For biological subjects, you MUST populate exactly 2 alternative species in the \`candidates\` array. For non-biological subjects, use an empty \`candidates\` array.
- Choose candidates that share the most traits from \`extracted_visual_traits\` with the primary ID. Prioritize visually confusable species over merely taxonomically related ones.
- **Distinguishing Feature:** For each candidate, provide the single most important observable morphological difference that separates it from your primary ID. State this as a concise clause referencing a specific visible trait (e.g., "cap margin lacks striations present on primary"). Do NOT repeat the species name here.

## Image Quality
Score the image as a reference photo across these dimensions:
- **sharpness:** (1–10) Focus and absence of motion blur.
- **framing:** (1–10) Subject fully in frame and isolated from chaotic background.
- **diagnostic_utility:** (1–10) Taxonomic identification features clearly displayed (e.g., leaf venation, plumage, bark texture).
- **overall_score:** (0–100) Holistic reference quality synthesizing all three dimensions.

## Pet Identification
Populate \`pet_identification\` only for domestic dogs and domestic cats. Use null for all other taxa.
- **species_group:** \`dog\` for \`Canis lupus familiaris\`, \`cat\` for \`Felis catus\`.
- **label:** Breed, visible breed mix, coat pattern, or body type in Title Case. Never return generic labels like Dog, Cat, Domestic Dog, Domestic Cat, or House Cat.
- **label_type:** \`breed\`, \`breed_mix\`, \`coat_pattern\`, or \`body_type\`.
- **confidence_score:** Confidence in the pet-specific label, based only on visible morphology.
- **evidence:** 1–3 short visual cues supporting the label.

## Darwin Core Semantics Dictionary
Output fields must align semantically with the Darwin Core data standard:

**life_stage:**
- \`egg\`: unhatched egg or egg mass
- \`larva\`: pre-metamorphic stage (caterpillar, grub, maggot, naiad, tadpole)
- \`pupa\`: chrysalis, cocoon, or pupal case
- \`nymph\`: hemimetabolous immature insect (lacking functional wings)
- \`juvenile\`: post-metamorphic immature resembling adult
- \`subadult\`: nearly adult retaining visible juvenile features
- \`adult\`: sexually mature individual
- \`seedling\`: plant from germination through first true leaf
- \`sapling\`: established juvenile woody plant prior to reproduction
- \`unknown\`: genuinely indeterminate from image

**reproductive_condition:** (Apply strictly to primary subject)
- \`flowering\`: one/more open flowers visible
- \`fruiting\`: ripe/unripe fruit, berries, cones, seed pods 
- \`budding\`: unopened flower/leaf buds only
- \`vegetative\`: active growth, no reproductive structures
- \`sporing\`: visible spore-bearing structures (sori, gills, pores)
- \`pregnant\`: viviparous mammal with visible abdominal enlargement
- \`gravid\`: oviparous animal carrying mature eggs internally
- \`mating\`: direct copulation/mating behaviour observed
- \`spawning\`: aquatic broadcast spawning event
- \`nesting\`: active nest construction, egg brooding, chick incubation
- \`dormant\`: seasonal dormancy (leaf drop, torpor, aestivation)
- \`not_applicable\`: indeterminate, not visible, or taxon lacks states

**sex:** (Apply strictly to primary subject)
- \`female\`: diagnostic visible or described evidence indicates female
- \`male\`: diagnostic visible or described evidence indicates male
- \`hermaphrodite\`: diagnostic evidence indicates simultaneous male/female reproductive function
- \`mixed\`: multiple primary-subject individuals of different sexes are visible or described
- \`cannot_determine\`: biological subject present but sex is not diagnostically supported
- \`not_applicable\`: non-sexed organism/state or human subject where sex/gender must not be inferred

**ecology_type:**
- \`wild\`: natural/semi-natural habitat, no intensive management
- \`urban\`: human-modified landscape (gardens, parks, roadsides, buildings)
- \`domesticated\`: captive animal, cultivated plant, farmed organism
`;

// Shared schema properties present in both the biological and non-biological branches.
// Extracted to a factory function so both branches reference identical field definitions
// without duplication. Called at schema-build time (module scope, warm isolate cached).
const sharedProperties = (): Record<string, ResponseSchema> => ({
  extracted_visual_traits: {
    type: SchemaType.ARRAY,
    items: { type: SchemaType.STRING },
    description:
      "Extract exactly 3 distinct physical or structural traits observed in the visual evidence (e.g. 'smooth texture', 'embedded in concrete', 'green leaves').",
  },
  ai_reasoning: {
    type: SchemaType.STRING,
    description:
      "A 1-3 sentence intelligence analysis breaking down the exact reasoning behind this identification. Detail the specific physical attributes, structural nuances, and visual evidence that substantiate this classification.",
  },
  is_biological_subject: { type: SchemaType.BOOLEAN },
  is_live_capture: { type: SchemaType.BOOLEAN },
  confidence_score: {
    type: SchemaType.NUMBER,
    minimum: 0,
    maximum: 1,
    description:
      "Calibrated confidence in the primary identification (0.0–1.0). " +
      "ANCHORS: " +
      "≥0.95 = key diagnostic features are unambiguously visible in the visual evidence AND no visually confusable species shares those exact features in the same region and season; " +
      "0.80–0.94 = confident but one or more similar species cannot be definitively ruled out from the visual evidence alone; " +
      "0.60–0.79 = probable identification, multiple visually similar species remain plausible; " +
      "<0.60 = uncertain, visual evidence lacks sufficient diagnostic detail for reliable species-level identification. " +
      "CRITICAL: base confidence ONLY on morphological features visible in the visual evidence. " +
      "NEVER inflate it because a species is locally common, seasonally expected, or habitat-appropriate — those factors resolve the primary identification but do not raise confidence. " +
      "Most field photographs of common species warrant a score of 0.70–0.88.",
  },
  candidates: {
    type: SchemaType.ARRAY,
    items: {
      type: SchemaType.OBJECT,
      properties: {
        scientific_name: { type: SchemaType.STRING },
        confidence_score: {
          type: SchemaType.NUMBER,
          minimum: 0,
          maximum: 1,
        },
        distinguishing_feature: {
          type: SchemaType.STRING,
          description:
            "The single most important visual feature that separates this candidate from the primary identification. Must reference a specific trait from extracted_visual_traits or a directly observable morphological difference (e.g. 'cap margin lacks striations', 'wing bars absent', 'leaf base asymmetric'). One concise clause — do not repeat the species name.",
        },
      },
      required: [
        "scientific_name",
        "confidence_score",
        "distinguishing_feature",
      ],
    },
    description:
      "For biological subjects, provide exactly 2 alternative species candidates grounded in the extracted_visual_traits. For non-biological subjects, return an empty array. Choose candidates that share the most observed traits with the primary identification — not just taxonomically related species. For each, distinguishing_feature must name the specific observable difference that rules it in or out.",
  },
  image_quality: {
    type: SchemaType.OBJECT,
    properties: {
      sharpness: {
        type: SchemaType.INTEGER,
        minimum: 1,
        maximum: 10,
      },
      framing: {
        type: SchemaType.INTEGER,
        minimum: 1,
        maximum: 10,
      },
      diagnostic_utility: {
        type: SchemaType.INTEGER,
        minimum: 1,
        maximum: 10,
      },
      overall_score: {
        type: SchemaType.INTEGER,
        minimum: 0,
        maximum: 100,
      },
    },
    required: ["sharpness", "framing", "diagnostic_utility", "overall_score"],
    description:
      "Photographic quality scores for encyclopedic reference use. sharpness 1–10: focus and motion blur. framing 1–10: subject fully visible and isolated. diagnostic_utility 1–10: taxonomic features clearly displayed. overall_score 0–100: holistic reference quality.",
  },
  pet_identification: {
    type: SchemaType.OBJECT,
    nullable: true,
    properties: {
      species_group: {
        type: SchemaType.STRING,
        format: "enum",
        enum: ["dog", "cat"],
      },
      label: {
        type: SchemaType.STRING,
        description:
          "Breed, visible breed mix, coat pattern, or body type in Title Case. Never generic Dog/Cat labels.",
      },
      label_type: {
        type: SchemaType.STRING,
        format: "enum",
        enum: ["breed", "breed_mix", "coat_pattern", "body_type"],
      },
      confidence_score: {
        type: SchemaType.NUMBER,
        minimum: 0,
        maximum: 1,
        description:
          "Confidence in this pet-specific label from visible morphology only.",
      },
      evidence: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
      },
    },
    required: [
      "species_group",
      "label",
      "label_type",
      "confidence_score",
      "evidence",
    ],
    description:
      "Optional domestic dog/cat pet label. Null for all non-dog/cat taxa and for unsupported pet labels.",
  },
});

// Required fields common to both branches.
const SHARED_REQUIRED = [
  "is_biological_subject",
  "is_live_capture",
  "extracted_visual_traits",
  "ai_reasoning",
  "confidence_score",
  "image_quality",
  "candidates",
] as const;

// Schema cache keyed by diagnosticTrigger so warm isolate re-use avoids repeated
// object construction across requests. Two entries maximum (flash=0.95, pro=0.85).
// The trigger value does not currently affect schema shape but the cache is keyed
// by it for forward compatibility if per-tier schema divergence is introduced later.
const schemaCache = new Map<number, ResponseSchema>();

export const getMerianResponseSchema = (
  diagnosticTrigger: number,
): ResponseSchema => {
  if (schemaCache.has(diagnosticTrigger)) {
    return schemaCache.get(diagnosticTrigger)!;
  }

  // Flat schema: all fields in one object, biology-specific ones nullable.
  // Previously used anyOf [biologicalBranch, nonBiologicalBranch] to let Gemini
  // pick the right field set, but anyOf at the responseSchema root can cause the
  // Gemini API to reject the entire request with a structured-output validation
  // error before inference starts — the root schema must be a plain OBJECT.
  // The system instruction already tells the model to omit biology fields for
  // non-biological subjects (is_biological_subject=false), so the flat schema
  // produces equivalent output quality with universal API compatibility.
  const schema: ResponseSchema = {
    type: SchemaType.OBJECT,
    properties: {
      ...sharedProperties(),
      scientific_name: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Formally accepted binomial scientific name. Required for biological subjects and identifiable geological specimens. Null for manufactured, processed, or unidentifiable non-natural objects.",
      },
      common_name: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Most specific, commonly recognized English name in Title Case. Null for unidentifiable non-natural objects.",
      },
      ecology_type: {
        type: SchemaType.STRING,
        format: "enum",
        enum: ["wild", "urban", "domesticated", "unknown"],
        nullable: true,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      },
      is_invasive: {
        type: SchemaType.BOOLEAN,
        nullable: true,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      },
      invasive_status_region: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Biological subjects only. Region label used for the invasive-status assessment, such as 'Austin, TX', 'Central Texas', or 'Unavailable'. Null for non-biological subjects.",
      },
      invasive_rationale: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Biological subjects only. One concise sentence explaining the invasive-status assessment from the original identification reasoning, location context, species identity, and ecological context. Null for non-biological subjects.",
      },
      invasive_confidence: {
        type: SchemaType.NUMBER,
        minimum: 0,
        maximum: 1,
        nullable: true,
        description:
          "Biological subjects only. Confidence from 0.0 to 1.0 for the invasive-status assessment, separate from identification confidence. Null when location evidence is insufficient or subject is non-biological.",
      },
      life_stage: {
        type: SchemaType.STRING,
        format: "enum",
        enum: [
          "egg",
          "larva",
          "pupa",
          "nymph",
          "juvenile",
          "subadult",
          "adult",
          "seedling",
          "sapling",
          "unknown",
        ],
        nullable: true,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      },
      reproductive_condition: {
        type: SchemaType.STRING,
        format: "enum",
        enum: [
          "flowering",
          "fruiting",
          "budding",
          "vegetative",
          "sporing",
          "pregnant",
          "gravid",
          "mating",
          "spawning",
          "nesting",
          "dormant",
          "not_applicable",
        ],
        nullable: true,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      },
      sex: {
        type: SchemaType.STRING,
        format: "enum",
        enum: [
          "female",
          "male",
          "hermaphrodite",
          "mixed",
          "cannot_determine",
          "not_applicable",
        ],
        nullable: true,
        description:
          "Darwin Core sex for the primary biological subject. Use cannot_determine unless visible/described evidence is diagnostic. Null for non-biological subjects.",
      },
      sex_confidence: {
        type: SchemaType.NUMBER,
        minimum: 0,
        maximum: 1,
        nullable: true,
        description:
          "Confidence in the sex annotation from direct evidence only, 0.0–1.0. Null when sex is null, not_applicable, or cannot_determine.",
      },
      sex_evidence: {
        type: SchemaType.STRING,
        nullable: true,
        description:
          "Short phrase naming the exact evidence for sex, such as dimorphic plumage, antlers, flowers, gravid abdomen, or mating role. Null when unsupported.",
      },
      individual_count: {
        type: SchemaType.INTEGER,
        minimum: 1,
        maximum: 99999,
        nullable: true,
        description:
          "Number of distinct individuals of the primary species visible. Null when impossible to estimate or for non-biological subjects.",
      },
      ecological_interactions: {
        type: SchemaType.ARRAY,
        items: { type: SchemaType.STRING },
        nullable: true,
        description:
          "Active interactions with other biological organisms visible in the frame. Use complete phrases; do not end entries with ellipses or truncated wording. Null for non-biological subjects.",
      },
    },
    required: [...SHARED_REQUIRED],
  };

  schemaCache.set(diagnosticTrigger, schema);
  return schema;
};
