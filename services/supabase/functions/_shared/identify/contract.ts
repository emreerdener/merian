/**
 * One executable contract owns the Identify model boundary, the final Edge
 * response boundary, and the generated Swift DTO boundary.
 *
 * Keep this module dependency-free. It is imported by deployed Edge Functions
 * and by repository tooling.
 */

export type ContractKind =
  | "array"
  | "boolean"
  | "integer"
  | "number"
  | "object"
  | "string";

interface ContractNodeBase {
  readonly kind: ContractKind;
  readonly nullable?: boolean;
  readonly description?: string;
}

export interface StringContract extends ContractNodeBase {
  readonly kind: "string";
  readonly enum?: readonly string[];
  readonly minLength?: number;
  readonly maxLength?: number;
}

export interface BooleanContract extends ContractNodeBase {
  readonly kind: "boolean";
  readonly const?: boolean;
}

export interface NumberContract extends ContractNodeBase {
  readonly kind: "number" | "integer";
  readonly minimum: number;
  readonly maximum: number;
}

export interface ArrayContract extends ContractNodeBase {
  readonly kind: "array";
  readonly items: ContractNode;
  readonly minItems?: number;
  readonly maxItems?: number;
}

export interface SwiftObjectMetadata {
  readonly name: string;
  readonly parent?: string;
  readonly declarationOrder: number;
  readonly defaultPropertyOptional?: boolean;
}

export interface SwiftPropertyMetadata {
  readonly name?: string;
  readonly optional?: boolean;
}

export interface ContractField {
  readonly contract: ContractNode;
  readonly required: boolean;
  /**
   * false means the field is intentionally server-only and is not emitted in
   * the generated Swift DTO. An object without Swift metadata is likewise not
   * part of the Swift boundary.
   */
  readonly swift?: SwiftPropertyMetadata | false;
}

interface TypedContractField<
  C extends ContractNode,
  R extends boolean,
  S extends SwiftPropertyMetadata | false | undefined,
> extends ContractField {
  readonly contract: C;
  readonly required: R;
  readonly swift: S;
}

export interface ObjectContract extends ContractNodeBase {
  readonly kind: "object";
  readonly fields: Readonly<Record<string, ContractField>>;
  readonly unknownKeys: "reject" | "strip";
  readonly swift?: SwiftObjectMetadata;
}

export type ContractNode =
  | ArrayContract
  | BooleanContract
  | NumberContract
  | ObjectContract
  | StringContract;

function field<C extends ContractNode>(
  contract: C,
): TypedContractField<C, false, undefined>;
function field<
  C extends ContractNode,
  R extends boolean,
  S extends SwiftPropertyMetadata | false | undefined = undefined,
>(
  contract: C,
  required: R,
  swift?: S,
): TypedContractField<C, R, S>;
function field(
  contract: ContractNode,
  required = false,
  swift?: SwiftPropertyMetadata | false,
): ContractField {
  return { contract, required, swift };
}

const text = <
  const O extends Omit<StringContract, "kind"> = Record<
    never,
    never
  >,
>(
  options?: O,
): StringContract & O => ({ kind: "string", ...options } as StringContract & O);

const truth = <
  const O extends Omit<BooleanContract, "kind"> = Record<
    never,
    never
  >,
>(
  options?: O,
): BooleanContract & O => ({
  kind: "boolean",
  ...options,
} as BooleanContract & O);

const decimal = <
  const O extends Omit<
    NumberContract,
    "kind" | "minimum" | "maximum"
  > = Record<never, never>,
>(
  minimum: number,
  maximum: number,
  options?: O,
): NumberContract & O & { readonly kind: "number" } => ({
  kind: "number",
  minimum,
  maximum,
  ...options,
} as NumberContract & O & { readonly kind: "number" });

const integer = <
  const O extends Omit<
    NumberContract,
    "kind" | "minimum" | "maximum"
  > = Record<never, never>,
>(
  minimum: number,
  maximum: number,
  options?: O,
): NumberContract & O & { readonly kind: "integer" } => ({
  kind: "integer",
  minimum,
  maximum,
  ...options,
} as NumberContract & O & { readonly kind: "integer" });

const list = <
  I extends ContractNode,
  const O extends Omit<ArrayContract, "kind" | "items"> = Record<never, never>,
>(
  items: I,
  options?: O,
): Omit<ArrayContract, "items"> & O & { readonly items: I } => ({
  kind: "array",
  items,
  ...options,
} as Omit<ArrayContract, "items"> & O & { readonly items: I });

const object = <
  const F extends Readonly<Record<string, ContractField>>,
  const O extends Omit<ObjectContract, "kind" | "fields">,
>(
  fields: F,
  options: O,
): Omit<ObjectContract, "fields"> & O & { readonly fields: F } => ({
  kind: "object",
  fields,
  ...options,
} as Omit<ObjectContract, "fields"> & O & { readonly fields: F });

const confidence = decimal(0, 1);
const compactLabel = text({ minLength: 1, maxLength: 160 });
const generatedSentence = text({ minLength: 1, maxLength: 2_000 });
const url = text({ minLength: 1, maxLength: 4_096, nullable: true });

const modelCandidateContract = object(
  {
    scientific_name: field(
      text({ minLength: 1, maxLength: 255 }),
      true,
    ),
    confidence_score: field(confidence, true),
    distinguishing_feature: field(
      text({
        minLength: 1,
        maxLength: 500,
        description:
          "The single most important visual feature that separates this candidate from the primary identification. Must reference a specific trait from extracted_visual_traits or a directly observable morphological difference (e.g. 'cap margin lacks striations', 'wing bars absent', 'leaf base asymmetric'). One concise clause — do not repeat the species name.",
      }),
      true,
    ),
  },
  { unknownKeys: "strip" },
);

const imageQualityContract = object(
  {
    sharpness: field(integer(1, 10), true),
    framing: field(integer(1, 10), true),
    diagnostic_utility: field(integer(1, 10), true),
    overall_score: field(integer(0, 100), true),
  },
  {
    unknownKeys: "strip",
    description:
      "Photographic quality scores for encyclopedic reference use. sharpness 1–10: focus and motion blur. framing 1–10: subject fully visible and isolated. diagnostic_utility 1–10: taxonomic features clearly displayed. overall_score 0–100: holistic reference quality.",
  },
);

const petIdentificationContract = object(
  {
    species_group: field(
      text({ enum: ["dog", "cat"], maxLength: 3 }),
      true,
      { name: "speciesGroup" },
    ),
    label: field(
      text({
        minLength: 1,
        maxLength: 160,
        description:
          "Breed, visible breed mix, coat pattern, or body type in Title Case. Never generic Dog/Cat labels.",
      }),
      true,
    ),
    label_type: field(
      text({
        enum: ["breed", "breed_mix", "coat_pattern", "body_type"],
        maxLength: 20,
      }),
      true,
      { name: "labelType" },
    ),
    confidence_score: field(
      decimal(0, 1, {
        description:
          "Confidence in this pet-specific label from visible morphology only.",
      }),
      true,
      { name: "confidenceScore" },
    ),
    evidence: field(
      list(text({ minLength: 1, maxLength: 500 }), {
        minItems: 1,
        maxItems: 3,
      }),
      true,
    ),
  },
  {
    nullable: true,
    unknownKeys: "strip",
    description:
      "Optional domestic dog/cat pet label. Null for all non-dog/cat taxa and for unsupported pet labels.",
  },
);

/**
 * The exact structured-output object requested from Gemini. Provider schema
 * generation and runtime parsing both consume this value.
 */
export const merianModelContract = deepFreezeJson(object(
  {
    extracted_visual_traits: field(
      list(text({ minLength: 1, maxLength: 500 }), {
        minItems: 1,
        maxItems: 10,
        description:
          "Extract exactly 3 distinct physical or structural traits observed in the visual evidence (e.g. 'smooth texture', 'embedded in concrete', 'green leaves').",
      }),
      true,
    ),
    ai_reasoning: field(
      text({
        minLength: 1,
        maxLength: 2_000,
        description:
          "A 1-3 sentence intelligence analysis breaking down the exact reasoning behind this identification. Detail the specific physical attributes, structural nuances, and visual evidence that substantiate this classification.",
      }),
      true,
    ),
    is_biological_subject: field(
      truth({
        description:
          "Whether the intended primary visual subject is biological. True only when an organism, organism part, fossil, or preserved specimen is primary after evaluating whole-frame composition and any user description. False when biology is merely incidental background, peripheral, reflected, or displayed content while a non-biological subject dominates.",
      }),
      true,
    ),
    is_live_capture: field(truth(), true),
    confidence_score: field(
      decimal(0, 1, {
        description:
          "Calibrated confidence in the primary identification (0.0–1.0). ANCHORS: ≥0.95 = key diagnostic features are unambiguously visible in the visual evidence AND no visually confusable species shares those exact features in the same region and season; 0.80–0.94 = confident but one or more similar species cannot be definitively ruled out from the visual evidence alone; 0.60–0.79 = probable identification, multiple visually similar species remain plausible; <0.60 = uncertain, visual evidence lacks sufficient diagnostic detail for reliable species-level identification. CRITICAL: base confidence ONLY on morphological features visible in the visual evidence. NEVER inflate it because a species is locally common, seasonally expected, or habitat-appropriate — those factors resolve the primary identification but do not raise confidence. Most field photographs of common species warrant a score of 0.70–0.88.",
      }),
      true,
    ),
    candidates: field(
      list(modelCandidateContract, {
        minItems: 0,
        maxItems: 5,
        description:
          "For biological subjects, provide exactly 2 alternative species candidates grounded in the extracted_visual_traits. For non-biological subjects, return an empty array. Choose candidates that share the most observed traits with the primary identification — not just taxonomically related species. For each, distinguishing_feature must name the specific observable difference that rules it in or out.",
      }),
      true,
    ),
    image_quality: field(imageQualityContract, true),
    pet_identification: field(petIdentificationContract),
    scientific_name: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 255,
        description:
          "Formally accepted binomial scientific name. Required for biological subjects and identifiable geological specimens. Null for manufactured, processed, or unidentifiable non-natural objects.",
      }),
    ),
    common_name: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 255,
        description:
          "Most specific, commonly recognized English name in Title Case. Null for unidentifiable non-natural objects.",
      }),
    ),
    ecology_type: field(
      text({
        nullable: true,
        enum: ["wild", "urban", "domesticated", "unknown"],
        maxLength: 12,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      }),
    ),
    is_invasive: field(
      truth({
        nullable: true,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      }),
    ),
    invasive_status_region: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 160,
        description:
          "Biological subjects only. Region label used for the invasive-status assessment, such as 'Austin, TX', 'Central Texas', or 'Unavailable'. Null for non-biological subjects.",
      }),
    ),
    invasive_rationale: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 500,
        description:
          "Biological subjects only. One concise sentence explaining the invasive-status assessment from the original identification reasoning, location context, species identity, and ecological context. Null for non-biological subjects.",
      }),
    ),
    invasive_confidence: field(
      decimal(0, 1, {
        nullable: true,
        description:
          "Biological subjects only. Confidence from 0.0 to 1.0 for the invasive-status assessment, separate from identification confidence. Null when location evidence is insufficient or subject is non-biological.",
      }),
    ),
    life_stage: field(
      text({
        nullable: true,
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
        maxLength: 16,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      }),
    ),
    reproductive_condition: field(
      text({
        nullable: true,
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
        maxLength: 20,
        description:
          "Biological subjects only. Null for non-biological subjects.",
      }),
    ),
    sex: field(
      text({
        nullable: true,
        enum: [
          "female",
          "male",
          "hermaphrodite",
          "mixed",
          "cannot_determine",
          "not_applicable",
        ],
        maxLength: 20,
        description:
          "Darwin Core sex for the primary biological subject. Use cannot_determine unless visible/described evidence is diagnostic. Null for non-biological subjects.",
      }),
    ),
    sex_confidence: field(
      decimal(0, 1, {
        nullable: true,
        description:
          "Confidence in the sex annotation from direct evidence only, 0.0–1.0. Null when sex is null, not_applicable, or cannot_determine.",
      }),
    ),
    sex_evidence: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 500,
        description:
          "Short phrase naming the exact evidence for sex, such as dimorphic plumage, antlers, flowers, gravid abdomen, or mating role. Null when unsupported.",
      }),
    ),
    individual_count: field(
      integer(1, 99_999, {
        nullable: true,
        description:
          "Number of distinct individuals of the primary species visible. Null when impossible to estimate or for non-biological subjects.",
      }),
    ),
    ecological_interactions: field(
      list(text({ minLength: 1, maxLength: 500 }), {
        nullable: true,
        minItems: 0,
        maxItems: 10,
        description:
          "Active interactions with other biological organisms visible in the frame. Use complete phrases; do not end entries with ellipses or truncated wording. Null for non-biological subjects.",
      }),
    ),
  },
  { unknownKeys: "strip" },
));

export const audioSubjectTypes = [
  "identified_non_human",
  "unidentified_non_human",
  "human_only",
  "no_confident_biological_source",
] as const;
export type AudioProviderSubjectType = (typeof audioSubjectTypes)[number];

const audioCandidateContract = object(
  {
    ...modelCandidateContract.fields,
    distinguishing_feature: field(
      text({
        minLength: 1,
        maxLength: 500,
        description:
          "The single most important audible difference between this candidate and the primary identification, such as note shape, frequency range, rhythm, repetition, or harmonic structure. One concise clause.",
      }),
      true,
    ),
  },
  { unknownKeys: "strip" },
);

const audioImageQualityContract = object(
  imageQualityContract.fields,
  {
    unknownKeys: "strip",
    description:
      "Audio-only compatibility values. Return sharpness=10, framing=10, diagnostic_utility=10, and overall_score=100; these values do not describe a photograph.",
  },
);

/**
 * Private structured-output contract for audio-only provider calls. The
 * audio_subject_type discriminator is consumed and removed before the public
 * Identify response is assembled; it is not an API, DTO, or persistence field.
 */
export const merianAudioModelContract = deepFreezeJson(object(
  {
    ...merianModelContract.fields,
    extracted_visual_traits: field(
      list(text({ minLength: 1, maxLength: 500 }), {
        minItems: 1,
        maxItems: 10,
        description:
          "Despite the legacy field name, return exactly 3 distinct acoustic traits heard in the recording, such as frequency range, rhythm, repetition, note duration, or harmonic structure.",
      }),
      true,
    ),
    ai_reasoning: field(
      text({
        minLength: 1,
        maxLength: 2_000,
        description:
          "A 1-3 sentence acoustic diagnosis citing only audible evidence from the recording.",
      }),
      true,
    ),
    audio_subject_type: field(
      text({
        enum: audioSubjectTypes,
        maxLength: 31,
        description:
          "Classify acoustic sources before deriving the public identity fields. Use identified_non_human when a confident non-human animal is present and its taxon is resolved; unidentified_non_human when a confident non-human animal is present but its taxon is unresolved; human_only only when unmistakable human biological sound is present and no non-human animal is confidently present; and no_confident_biological_source for silence, handling, weather, mechanical, or indeterminate audio. Non-human animals always take precedence over Human.",
      }),
      true,
      false,
    ),
    is_biological_subject: field(
      truth({
        description:
          "Derive from audio_subject_type: true for either non-human state and human_only; false only for no_confident_biological_source.",
      }),
      true,
    ),
    is_live_capture: field(
      truth({
        description:
          "True for either non-human state and human_only; false for no_confident_biological_source.",
      }),
      true,
    ),
    confidence_score: field(
      decimal(0, 1, {
        description:
          "Confidence in the selected audio subject classification. Species uncertainty may lower taxonomic confidence but must not erase confident non-human animal presence.",
      }),
      true,
    ),
    candidates: field(
      list(audioCandidateContract, {
        minItems: 0,
        maxItems: 5,
        description:
          "Alternative acoustically plausible species only for identified_non_human. Return an empty array for unidentified_non_human, human_only, and no_confident_biological_source.",
      }),
      true,
    ),
    image_quality: field(audioImageQualityContract, true),
    pet_identification: field(petIdentificationContract),
    scientific_name: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 255,
        description:
          "Resolved non-human taxon for identified_non_human; canonical Homo sapiens for human_only; null for unidentified_non_human and no_confident_biological_source.",
      }),
    ),
    common_name: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 255,
        description:
          "Resolved animal common name, Unidentified Wildlife, Human, or No Wildlife Detected, consistent with audio_subject_type.",
      }),
    ),
  },
  { unknownKeys: "strip" },
));

const describeImageQualityContract = object(
  {
    sharpness: field(integer(0, 0), true),
    framing: field(integer(0, 0), true),
    diagnostic_utility: field(integer(0, 0), true),
    overall_score: field(integer(0, 0), true),
  },
  {
    unknownKeys: "strip",
    description:
      "No visual evidence is present for Describe observations, so every image-quality score is zero.",
  },
);

const describeCandidateContract = object(
  {
    ...modelCandidateContract.fields,
    distinguishing_feature: field(
      text({
        minLength: 1,
        maxLength: 500,
        description:
          "The single most important difference between this candidate and the primary identification, phrased in terms of the user's description (e.g. 'lacks the spotted pattern the user described').",
      }),
      true,
    ),
  },
  { unknownKeys: "strip" },
);

/** Structured-output object used by the text-only Identify Describe route. */
export const merianDescribeModelContract = deepFreezeJson(object(
  {
    ...merianModelContract.fields,
    extracted_visual_traits: field(
      list(text({ minLength: 1, maxLength: 500 }), {
        minItems: 1,
        maxItems: 10,
        description:
          "Extract exactly 3 distinct traits from the observation description (e.g. 'brown coloration', 'palm-sized', 'perching on tree bark'). Every trait must come directly from the user's description.",
      }),
      true,
    ),
    ai_reasoning: field(
      text({
        minLength: 1,
        maxLength: 2_000,
        description:
          "A 1–3 sentence identification analysis that references the user's specific descriptors and explains why they support this species over the alternatives.",
      }),
      true,
    ),
    is_live_capture: field(
      truth({
        const: false,
        description:
          "Always false for a recalled text description without live photographic evidence.",
      }),
      true,
    ),
    confidence_score: field(
      decimal(0, 1, {
        description:
          "Calibrated confidence based solely on the description's diagnostic specificity (0.0–1.0). ≥0.85 means the description maps unambiguously to one species in the stated region and season; 0.60–0.84 means confident but similar species cannot be ruled out; 0.40–0.59 means probable but lacking diagnostic detail; below 0.40 is too generic for reliable identification. Most descriptions warrant 0.45–0.75. Never inflate confidence from local abundance.",
      }),
      true,
    ),
    candidates: field(
      list(describeCandidateContract, {
        minItems: 0,
        maxItems: 5,
        description:
          "For biological descriptions, provide exactly 2 alternative species grounded in the observation description. For non-biological descriptions, return an empty array.",
      }),
      true,
    ),
    image_quality: field(describeImageQualityContract, true),
    sex_evidence: field(
      text({
        nullable: true,
        minLength: 1,
        maxLength: 500,
        description:
          "Short phrase naming the exact user-described evidence for sex. Null when the description does not support it.",
      }),
    ),
    ecological_interactions: field(
      list(text({ minLength: 1, maxLength: 500 }), {
        nullable: true,
        minItems: 0,
        maxItems: 10,
        description:
          "Active interactions with other biological organisms stated in the observation description. Null for non-biological subjects.",
      }),
    ),
  },
  { unknownKeys: "strip" },
));

const finalCandidateContract = object(
  {
    scientific_name: modelCandidateContract.fields.scientific_name,
    confidence_score: modelCandidateContract.fields.confidence_score,
    distinguishing_feature: field(
      modelCandidateContract.fields.distinguishing_feature.contract,
      true,
      { optional: true },
    ),
    common_name: field(text({ minLength: 1, maxLength: 255 })),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "IdentificationCandidate",
      parent: "EdgeResponse",
      declarationOrder: 30,
    },
  },
);

const finalImageQualityContract = object(
  {
    sharpness: field(integer(0, 10), true),
    framing: field(integer(0, 10), true),
    diagnostic_utility: field(integer(0, 10), true),
    overall_score: field(integer(0, 100), true),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "ImageQuality",
      parent: "EdgeResponse",
      declarationOrder: 40,
      defaultPropertyOptional: true,
    },
  },
);

const finalPetIdentificationContract = object(
  petIdentificationContract.fields,
  {
    nullable: true,
    unknownKeys: "strip",
    swift: {
      name: "PetIdentificationDTO",
      declarationOrder: 10,
    },
  },
);

const taxonomyContract = object(
  {
    kingdom: field(compactLabel),
    phylum: field(compactLabel),
    class: field(compactLabel, false, { name: "`class`" }),
    order: field(compactLabel),
    family: field(compactLabel),
    genus: field(compactLabel),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "Taxonomy",
      parent: "EdgeResponse",
      declarationOrder: 10,
      defaultPropertyOptional: true,
    },
  },
);

const insightContract = object(
  {
    ai_reasoning: field(generatedSentence),
    hazard_type: field(
      text({
        enum: [
          "none",
          "poisonous",
          "venomous",
          "allergenic",
          "irritant",
        ],
        maxLength: 16,
      }),
    ),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "Insight",
      parent: "EdgeResponse",
      declarationOrder: 20,
      defaultPropertyOptional: true,
    },
  },
);

const speciesInsightsContract = object(
  {
    habitat_description: field(
      text({ minLength: 1, maxLength: 10_000 }),
    ),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "SpeciesInsights",
      parent: "EdgeResponse",
      declarationOrder: 25,
      defaultPropertyOptional: true,
    },
  },
);

const edgeResponseContract = object(
  {
    scan_id: field(text({ minLength: 1, maxLength: 128 }), true),
    is_biological_subject: field(truth(), true),
    is_live_capture: field(truth(), true),
    ecology_type: field(merianModelContract.fields.ecology_type.contract),
    is_invasive: field(merianModelContract.fields.is_invasive.contract),
    invasive_status_region: field(
      merianModelContract.fields.invasive_status_region.contract,
    ),
    invasive_rationale: field(
      merianModelContract.fields.invasive_rationale.contract,
    ),
    invasive_confidence: field(
      merianModelContract.fields.invasive_confidence.contract,
    ),
    scientific_name: field(
      merianModelContract.fields.scientific_name.contract,
    ),
    common_name: field(merianModelContract.fields.common_name.contract),
    confidence_score: field(confidence, true),
    blur_score: field(decimal(0, 1), true),
    colors: field(
      list(compactLabel, { minItems: 0, maxItems: 20 }),
      true,
    ),
    group_tags: field(
      list(compactLabel, { nullable: true, minItems: 0, maxItems: 32 }),
    ),
    is_new_to_merian_dictionary: field(truth()),
    estimated_size_cm: field(
      decimal(0, 50_000, { nullable: true }),
      true,
    ),
    life_stage: field(merianModelContract.fields.life_stage.contract),
    reproductive_condition: field(
      merianModelContract.fields.reproductive_condition.contract,
    ),
    sex: field(merianModelContract.fields.sex.contract),
    sex_confidence: field(
      merianModelContract.fields.sex_confidence.contract,
    ),
    sex_evidence: field(merianModelContract.fields.sex_evidence.contract),
    individual_count: field(
      merianModelContract.fields.individual_count.contract,
    ),
    ecological_interactions: field(
      merianModelContract.fields.ecological_interactions.contract,
    ),
    taxonomy: field(taxonomyContract),
    insight_data: field(insightContract),
    species_insights: field(speciesInsightsContract),
    gbif_taxon_key: field(
      integer(0, Number.MAX_SAFE_INTEGER, { nullable: true }),
    ),
    wikipedia_url: field(url),
    wikipedia_overview: field(
      text({ nullable: true, minLength: 1, maxLength: 20_000 }),
    ),
    reference_image_url: field(url),
    iucn_red_list_status: field(compactLabel),
    inference_tier: field(
      text({ enum: ["flash", "pro"], maxLength: 5 }),
      true,
    ),
    alternative_common_names: field(
      list(text({ minLength: 1, maxLength: 255 }), {
        nullable: true,
        minItems: 0,
        maxItems: 100,
      }),
    ),
    pet_identification: field(finalPetIdentificationContract, true),
    candidates: field(
      list(finalCandidateContract, {
        nullable: true,
        minItems: 0,
        maxItems: 5,
      }),
      true,
    ),
    image_quality: field(finalImageQualityContract, true),
    // Retained in the server payload for persistence/debugging. iOS receives
    // reasoning from insight_data and intentionally ignores these two fields.
    ai_reasoning: field(generatedSentence, true, false),
    extracted_visual_traits: field(
      merianModelContract.fields.extracted_visual_traits.contract,
      true,
      false,
    ),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "EdgeResponse",
      declarationOrder: 20,
      defaultPropertyOptional: true,
    },
  },
);

const entitlementSnapshotContract = object(
  {
    current_plan: field(
      text({
        enum: [
          "free",
          "pro_paid",
          "pro_trial",
          "pro_complimentary",
        ],
        maxLength: 24,
      }),
      true,
      { name: "currentPlan" },
    ),
    current_tier: field(
      text({ enum: ["free", "pro"], maxLength: 4 }),
      true,
      { name: "currentTier" },
    ),
    is_paid: field(truth(), true, { name: "isPaid" }),
    scans_remaining: field(integer(0, 3), true, {
      name: "scansRemaining",
    }),
    scans_available_to_start: field(integer(0, 3), true, {
      name: "scansAvailableToStart",
    }),
    in_flight_count: field(integer(0, Number.MAX_SAFE_INTEGER), true, {
      name: "inFlightCount",
    }),
    entitlement_version: field(
      integer(1, Number.MAX_SAFE_INTEGER),
      true,
      { name: "entitlementVersion" },
    ),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "EntitlementSnapshotDTO",
      declarationOrder: 3,
    },
  },
);

const scanEntitlementMetadataContract = object(
  {
    user_id: field(text({ minLength: 36, maxLength: 36 }), true, {
      name: "userID",
    }),
    plan_used: field(
      text({
        enum: [
          "free",
          "pro_paid",
          "pro_trial",
          "pro_complimentary",
        ],
        maxLength: 24,
      }),
      true,
      { name: "planUsed" },
    ),
    credit_consumed: field(truth(), true, {
      name: "creditConsumed",
    }),
    entitlement_after: field(entitlementSnapshotContract, true, {
      name: "entitlementAfter",
    }),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "ScanEntitlementMetadataDTO",
      declarationOrder: 2,
    },
  },
);

/** Exact successful JSON envelope returned by Identify Edge Functions. */
export const identifyWireEnvelopeContract = deepFreezeJson(object(
  {
    success: field(truth({ const: true }), true, { optional: true }),
    data: field(edgeResponseContract, true),
    entitlement: field(scanEntitlementMetadataContract, false, {
      optional: true,
    }),
  },
  {
    unknownKeys: "strip",
    swift: {
      name: "EdgeResponseWrapper",
      declarationOrder: 0,
    },
  },
));

type RequiredFieldNames<
  F extends Readonly<Record<string, ContractField>>,
> = {
  [K in keyof F]: F[K] extends { readonly required: true } ? K : never;
}[keyof F];

type OptionalFieldNames<
  F extends Readonly<Record<string, ContractField>>,
> = Exclude<keyof F, RequiredFieldNames<F>>;

type InferObject<
  F extends Readonly<Record<string, ContractField>>,
> =
  & {
    -readonly [K in RequiredFieldNames<F>]-?: InferContract<
      F[K]["contract"]
    >;
  }
  & {
    -readonly [K in OptionalFieldNames<F>]?: InferContract<
      F[K]["contract"]
    >;
  };

type WithContractNullability<N, V> = N extends {
  readonly nullable: true;
} ? V | null
  : V;

export type InferContract<N extends ContractNode> = WithContractNullability<
  N,
  N extends {
    readonly kind: "string";
    readonly enum: readonly (infer E extends string)[];
  } ? E
    : N extends { readonly kind: "string" } ? string
    : N extends {
      readonly kind: "boolean";
      readonly const: infer B extends boolean;
    } ? B
    : N extends { readonly kind: "boolean" } ? boolean
    : N extends { readonly kind: "integer" | "number" } ? number
    : N extends {
      readonly kind: "array";
      readonly items: infer I extends ContractNode;
    } ? InferContract<I>[]
    : N extends {
      readonly kind: "object";
      readonly fields: infer F extends Readonly<
        Record<string, ContractField>
      >;
    } ? InferObject<F>
    : never
>;

/** TypeScript boundaries are derived from the executable contracts as well. */
type RawMerianIdentification = InferContract<
  typeof merianModelContract
>;
type RawMerianAudioIdentification = InferContract<
  typeof merianAudioModelContract
>;
type RawDescribeIdentification = InferContract<
  typeof merianDescribeModelContract
>;
export type MerianIdentification = RawMerianIdentification & {
  /** Deterministically derived after provider validation. */
  blur_score?: number;
};
export type MerianAudioIdentification = RawMerianAudioIdentification & {
  /** Deterministically derived after provider validation. */
  blur_score?: number;
};
export type IdentifySuccessEnvelope = InferContract<
  typeof identifyWireEnvelopeContract
>;
export type ClientPayload = IdentifySuccessEnvelope["data"];
export type DescribeIdentification = RawDescribeIdentification & {
  blur_score?: number;
};

export interface PortableProviderSchema {
  readonly type:
    | "ARRAY"
    | "BOOLEAN"
    | "INTEGER"
    | "NUMBER"
    | "OBJECT"
    | "STRING";
  readonly nullable?: boolean;
  readonly description?: string;
  readonly format?: "enum";
  readonly enum?: readonly string[];
  readonly minimum?: number;
  readonly maximum?: number;
  /** @google/genai@1.0.0 represents OpenAPI int64 constraints as strings. */
  readonly minLength?: string;
  readonly maxLength?: string;
  readonly minItems?: string;
  readonly maxItems?: string;
  readonly items?: PortableProviderSchema;
  readonly properties?: Readonly<Record<string, PortableProviderSchema>>;
  readonly required?: readonly string[];
}

/**
 * Generate the provider schema from the same discriminated contract used at
 * runtime. No source-code symbol lookup or property-name inference is involved.
 */
export function providerSchemaFromContract(
  contract: ContractNode,
): PortableProviderSchema {
  const common = {
    ...(contract.nullable === true ? { nullable: true } : {}),
    ...(contract.description ? { description: contract.description } : {}),
  };
  switch (contract.kind) {
    case "string":
      return {
        type: "STRING",
        ...common,
        ...(contract.minLength !== undefined
          ? { minLength: String(contract.minLength) }
          : {}),
        ...(contract.maxLength !== undefined
          ? { maxLength: String(contract.maxLength) }
          : {}),
        ...(contract.enum
          ? { format: "enum" as const, enum: contract.enum }
          : {}),
      };
    case "boolean":
      return { type: "BOOLEAN", ...common };
    case "integer":
    case "number":
      return {
        type: contract.kind === "integer" ? "INTEGER" : "NUMBER",
        minimum: contract.minimum,
        maximum: contract.maximum,
        ...common,
      };
    case "array":
      return {
        type: "ARRAY",
        items: providerSchemaFromContract(contract.items),
        ...common,
        ...(contract.minItems !== undefined
          ? { minItems: String(contract.minItems) }
          : {}),
        ...(contract.maxItems !== undefined
          ? { maxItems: String(contract.maxItems) }
          : {}),
      };
    case "object": {
      const properties: Record<string, PortableProviderSchema> = {};
      const required: string[] = [];
      for (const [name, definition] of Object.entries(contract.fields)) {
        properties[name] = providerSchemaFromContract(definition.contract);
        if (definition.required) required.push(name);
      }
      return {
        type: "OBJECT",
        properties,
        ...(required.length > 0 ? { required } : {}),
        ...common,
      };
    }
  }
}

export interface ContractIssue {
  readonly path: string;
  readonly message: string;
}

export class ContractValueError extends Error {
  override readonly name = "ContractValueError";

  constructor(readonly issues: readonly ContractIssue[]) {
    super(
      `Contract validation failed:\n${
        issues.map((issue) => `- ${issue.path}: ${issue.message}`).join("\n")
      }`,
    );
  }
}

function isJsonObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" &&
    !Array.isArray(value);
}

function childPath(path: string, child: string): string {
  return path ? `${path}.${child}` : child;
}

function parseNode(
  contract: ContractNode,
  value: unknown,
  path: string,
  issues: ContractIssue[],
): unknown {
  if (value === null) {
    if (contract.nullable) return null;
    issues.push({ path, message: "null is not allowed" });
    return undefined;
  }

  switch (contract.kind) {
    case "string": {
      if (typeof value !== "string") {
        issues.push({ path, message: "expected a string" });
        return undefined;
      }
      if (
        contract.minLength !== undefined &&
        value.length < contract.minLength
      ) {
        issues.push({
          path,
          message: `length must be at least ${contract.minLength}`,
        });
      }
      if (
        contract.maxLength !== undefined &&
        value.length > contract.maxLength
      ) {
        issues.push({
          path,
          message: `length must be at most ${contract.maxLength}`,
        });
      }
      if (contract.enum && !contract.enum.includes(value)) {
        issues.push({
          path,
          message: `expected one of ${contract.enum.join(", ")}`,
        });
      }
      return value;
    }
    case "boolean":
      if (typeof value !== "boolean") {
        issues.push({ path, message: "expected a boolean" });
        return undefined;
      }
      if (contract.const !== undefined && value !== contract.const) {
        issues.push({
          path,
          message: `must be ${contract.const}`,
        });
      }
      return value;
    case "integer":
    case "number": {
      if (
        typeof value !== "number" || !Number.isFinite(value) ||
        (contract.kind === "integer" && !Number.isSafeInteger(value))
      ) {
        issues.push({
          path,
          message: contract.kind === "integer"
            ? "expected a finite safe integer"
            : "expected a finite number",
        });
        return undefined;
      }
      if (value < contract.minimum || value > contract.maximum) {
        issues.push({
          path,
          message:
            `must be between ${contract.minimum} and ${contract.maximum}`,
        });
      }
      return value;
    }
    case "array": {
      if (!Array.isArray(value)) {
        issues.push({ path, message: "expected an array" });
        return undefined;
      }
      if (
        contract.minItems !== undefined &&
        value.length < contract.minItems
      ) {
        issues.push({
          path,
          message: `must contain at least ${contract.minItems} item(s)`,
        });
      }
      if (
        contract.maxItems !== undefined &&
        value.length > contract.maxItems
      ) {
        issues.push({
          path,
          message: `must contain at most ${contract.maxItems} item(s)`,
        });
      }
      return value.map((item, index) =>
        parseNode(contract.items, item, `${path}[${index}]`, issues)
      );
    }
    case "object": {
      if (!isJsonObject(value)) {
        issues.push({ path, message: "expected an object" });
        return undefined;
      }
      const result: Record<string, unknown> = {};
      for (const [name, definition] of Object.entries(contract.fields)) {
        const propertyPath = childPath(path, name);
        const propertyValue = value[name];
        if (propertyValue === undefined) {
          if (definition.required) {
            issues.push({
              path: propertyPath,
              message: "required property is missing",
            });
          }
          continue;
        }
        result[name] = parseNode(
          definition.contract,
          propertyValue,
          propertyPath,
          issues,
        );
      }
      if (contract.unknownKeys === "reject") {
        for (const name of Object.keys(value)) {
          if (!(name in contract.fields)) {
            issues.push({
              path: childPath(path, name),
              message: "unknown property is not allowed",
            });
          }
        }
      }
      return result;
    }
  }
}

export function parseContract(
  contract: ContractNode,
  value: unknown,
  path = "$",
): unknown {
  const issues: ContractIssue[] = [];
  const parsed = parseNode(contract, value, path, issues);
  if (issues.length > 0) throw new ContractValueError(issues);
  return parsed;
}

export function parseMerianIdentification(
  value: unknown,
): MerianIdentification {
  return parseContract(
    merianModelContract,
    value,
    "model_response",
  ) as MerianIdentification;
}

export function parseMerianAudioIdentification(
  value: unknown,
): MerianAudioIdentification {
  return parseContract(
    merianAudioModelContract,
    value,
    "audio_model_response",
  ) as MerianAudioIdentification;
}

export function parseDescribeIdentification(
  value: unknown,
): DescribeIdentification {
  return parseContract(
    merianDescribeModelContract,
    value,
    "describe_model_response",
  ) as DescribeIdentification;
}

export function parseIdentifySuccessEnvelope(
  value: unknown,
): IdentifySuccessEnvelope {
  const parsed = parseContract(
    identifyWireEnvelopeContract,
    value,
    "response",
  ) as IdentifySuccessEnvelope;
  return deepFreezeJson(parsed);
}

function deepFreezeJson<T>(value: T): T {
  if (value !== null && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreezeJson(child);
  }
  return value;
}
