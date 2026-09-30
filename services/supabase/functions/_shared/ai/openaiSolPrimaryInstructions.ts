/** A new experiment; the failed rank-limits profile remains frozen. */
const edits = [
  [
    "when not alive — identify these to the species level.",
    "when not alive — identify these to the most specific supported resolution.",
  ],
  [
    "`ecological_interactions`; use an empty `candidates` array.",
    "`ecological_interactions`; use null for `candidates` and `pet_identification`.",
  ],
  [
    "`common_name` must be maximally specific in Title Case.",
    "`common_name` must be in Title Case and match the explicit `resolution`. Use a group label for a genus or family, never one possible species name.",
  ],
  [
    '`scientific_name` MUST be the currently accepted binomial recognized by GBIF, ITIS, or Catalogue of Life.\n   - Never return author citations (e.g., omit "(Linnaeus, 1758)"), hybrid markers (×), or infraspecific ranks unless it is the minimal determinate rank (e.g., *Brassica oleracea var. italica*).\n   - Return a genus-level name alone (without "sp.") ONLY when species determination is impossible. Never fabricate names.',
    '`scientific_name` must name the taxon at the declared species, genus or family resolution. Use a species only when the supplied visual evidence distinguishes it from plausible lookalikes. Otherwise choose a supported genus or family; use null for unresolved_biological. Never fabricate names or return author citations or uncertainty qualifiers such as "sp.".\n   - Hybrid, cultivar and other infraspecific names are outside this contract. Never shorten such a name to invent an accepted parent. Use an independently supported species, genus or family; otherwise return unresolved_biological. Preserve the existing domestic-dog convention Canis lupus familiaris and domestic-cat convention Felis catus.\n   - Preserve a species answer when diagnostic evidence supports it; do not reduce every result to a broader rank. Geological Exceptions remain applicable.',
  ],
  [
    "individuals of the primary species in the frame",
    "individuals of the primary biological subject in the frame",
  ],
  [
    "When multiple species are visually equally plausible, use GPS location and current month as a tiebreaker. Prefer the species with higher documented observation frequency in that region/season.",
    "Use only supplied location and month, within the rank supported by visible evidence. Regional frequency, season or popularity cannot replace a missing diagnostic feature or narrow a genus to a species. Never invent locality or distribution evidence.",
  ],
  [
    "Express genuine uncertainty through a lower `confidence_score` and populated `candidates` array rather than hallucinating or alternating primary identifications.",
    "Declare the supported `resolution` and keep the names, alternatives and explanation consistent with it. A lower `confidence_score` or disclaimer cannot justify an unsupported species name. Missing, obscured or unphotographed features are unknown, not absent. State observed support and any material limitation in the existing explanation format.",
  ],
  [
    "For biological subjects, you MUST populate exactly 2 alternative species in the `candidates` array. For non-biological subjects, use an empty `candidates` array.",
    "For species resolution, include zero to two evidence-supported alternative species in `candidates`, each with `taxon_rank=species`. Use an empty array when none is supported. For every other resolution, return null for `candidates` and `pet_identification`.",
  ],
  [
    "Choose candidates that share the most traits from `extracted_visual_traits` with the primary ID. Prioritize visually confusable species over merely taxonomically related ones.",
    "Choose visually confusable species grounded in observed traits. Do not invent alternatives to fill an array or list broader taxa as species.",
  ],
  [
    'For each candidate, provide the single most important observable morphological difference that separates it from your primary ID. State this as a concise clause referencing a specific visible trait (e.g., "cap margin lacks striations present on primary"). Do NOT repeat the species name here.',
    "For each candidate, name a specific observed distinction, or explicitly the additional distinguishing feature that would need to be seen. Do not describe an unseen feature as absent or claim it was observed. Keep one concise clause without repeating the species name.",
  ],
] as const;

export function solPhotoPrimaryInstructions(baseline: string): string {
  const projected = edits.reduce((value, [before, after]) => {
    if (value.split(before).length !== 2) {
      throw new Error("sol_primary_candidate_baseline_drift");
    }
    return value.replace(before, after);
  }, baseline);
  return projected + `

# Explicit Primary Resolution
Return exactly one resolution: species, genus, family, unresolved_biological or non_biological.
- Species, genus and family require a scientific name at that declared rank and is_biological_subject=true.
- Unresolved_biological means an organism/specimen is primary but none of those ranks is supported: scientific_name=null and is_biological_subject=true.
- Non_biological requires is_biological_subject=false; retain existing mineral/object naming.
- Never infer or justify a rank from name length, a confidence score, a subscription tier or popularity. Do not invent missing diagnostic features, lineage or species-level invasive status for a broader answer.
- If leaves are visible but a distinguishing flower is not shown, describe the visible leaves and say the flower was not shown; do not say flowers are absent. Select only the rank that the visible evidence supports. A useful broader answer must not hide a species guess in its common name or explanation.
Keep the existing 1–3 sentence explanation format. Do not add a chain of thought, extra fields or a user verification claim. The application constructs the versioned primary snapshot; return only this model schema.`;
}
