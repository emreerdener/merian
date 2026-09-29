/** Offline semantics only. No enrichment, persistence or production provenance. */
import {
  type ClientPayload,
  normalizePrimaryIdentification,
} from "../identify/contract.ts";
import {
  type IdentificationNormalizationContext,
  normalizeIdentification,
} from "../identify/normalizeIdentification.ts";
import { sanitizeScientificName } from "../../identify/sanitize.ts";
import { decodeSolPhotoPrimaryDraft } from "./openaiSolPrimaryContract.ts";

export function normalizeSolPhotoPrimaryDraft(
  value: unknown,
  context: IdentificationNormalizationContext,
) {
  if (
    !context.hasVisualEvidence || context.hasAudioEvidence ||
    context.confidencePolicy.kind !== "unqualified"
  ) throw new Error("sol_primary_context_unsupported");
  const { resolution, candidates, ...draft } = decodeSolPhotoPrimaryDraft(
    value,
  );
  const normalized = normalizeIdentification({
    ...draft,
    candidates: (candidates ?? []).map(({ taxon_rank: _rank, ...c }) => c),
  }, context);
  const demoted = normalized.diagnostics.some((d) =>
    d.event === "processed_material_demoted"
  );
  const effectiveResolution = demoted ? "non_biological" : resolution;
  if (
    !demoted && resolution !== "species" && draft.scientific_name &&
    normalized.identification.scientific_name !==
      sanitizeScientificName(draft.scientific_name)
  ) throw new Error("sol_primary_broader_name_changed");
  const primary = normalizePrimaryIdentification(effectiveResolution, {
    is_biological_subject: normalized.identification.is_biological_subject,
    scientific_name: normalized.identification.scientific_name ?? null,
    common_name: normalized.identification.common_name ?? null,
  });
  const rankedCandidates = primary.resolution === "species"
    ? normalized.identification.candidates.map((c, index) => ({
      ...c,
      taxon_rank: candidates![index].taxon_rank,
    }))
    : null;
  const identification = {
    ...normalized.identification,
    scientific_name: primary.scientific_name,
    common_name: primary.common_name,
    candidates: rankedCandidates,
    pet_identification: primary.resolution === "species"
      ? normalized.identification.pet_identification
      : null,
  };
  return {
    ...normalized,
    identification,
    clientCandidates: rankedCandidates as ClientPayload["candidates"],
    primary,
  };
}
