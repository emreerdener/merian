/** Prospective offline diagnostics. Never changes a closed study or logs prose. */
import {
  parseMerianIdentification,
  type PrimaryIdentification,
} from "../../functions/_shared/identify/contract.ts";
import { normalizeIdentification } from "../../functions/_shared/identify/normalizeIdentification.ts";
import { decodeSolPhotoPrimaryDraft } from "../../functions/_shared/ai/openaiSolPrimaryContract.ts";
import { normalizeSolPhotoPrimaryDraft } from "../../functions/_shared/ai/openaiSolPrimaryNormalization.ts";
import {
  canonicalizeDomesticPetScientificName,
  sanitizeScientificName,
} from "../../functions/identify/sanitize.ts";
import type { Taxon } from "./contracts.ts";
import {
  type IdentityMapping,
  noIdentityMapping,
  resolveTaxon,
  type ReviewedTaxonomy,
} from "./taxonomy.ts";
import { parseConfidenceObservation } from "./confidenceScoring.ts";

type Resolution = PrimaryIdentification["resolution"];
const context = {
  hasVisualEvidence: true,
  hasAudioEvidence: false,
  hasInvasiveLocationContext: false,
  confidencePolicy: { kind: "unqualified" as const },
};
type NameFlags = { present: boolean; annotation: boolean };
export interface DevelopmentDiagnostics {
  version: "photo_development_diagnostics_v1";
  stage: "decode" | "normalization" | "taxonomy";
  status: "rejected" | "accepted" | "rank_conflict";
  before: NameFlags;
  after: NameFlags | null;
  sanitizerChanged: boolean | null;
  petAliasChanged: boolean | null;
  nameChanged: boolean | null;
  processedMaterialDemoted: boolean;
  declaredResolution: Resolution | null;
  effectiveResolution: Resolution | null;
  beforeMapping: IdentityMapping | null;
  afterMapping: IdentityMapping | null;
  catalogRank: Taxon["rank"] | null;
  rankAgreement:
    | "not_declared"
    | "not_applicable"
    | "unverified"
    | "consistent"
    | "conflict";
}

// This is only a lexical flag. It cannot prove a name's validity or rank.
function flags(name: string | null | undefined): NameFlags {
  return {
    present: !!name,
    annotation: !!name &&
      /[().'‘’"“”×]|(?:^|\s)(?:x|sp|spp|cf|aff|var|subsp|ssp|cv|complex|group)(?:\s|$)/iu
        .test(name),
  };
}

/** Only read a bounded field for rejected-input diagnostics; never return it. */
function boundedName(value: unknown): string | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const name = (value as Record<string, unknown>).scientific_name;
  return typeof name === "string" && name.length <= 255 ? name : null;
}

/**
 * Accept only a provider draft held in memory. Returns bounded facts and the
 * existing scorer projection; no names, explanations or normalization events.
 * Callers still own moderation, accounting, claims and collection authorization.
 */
export function projectDevelopmentDraft(
  caseId: string,
  profile: "legacy" | "explicit_primary",
  draft: unknown,
  taxonomy: ReviewedTaxonomy,
) {
  const diagnostics: DevelopmentDiagnostics = {
    version: "photo_development_diagnostics_v1",
    stage: "decode",
    status: "rejected",
    before: flags(boundedName(draft)),
    after: null,
    sanitizerChanged: null,
    petAliasChanged: null,
    nameChanged: null,
    processedMaterialDemoted: false,
    declaredResolution: null,
    effectiveResolution: null,
    beforeMapping: null,
    afterMapping: null,
    catalogRank: null,
    rankAgreement: "not_declared",
  };
  const invalid = parseConfidenceObservation({
    prediction: { caseId, outcome: "invalid_output" },
    mapping: null,
  });
  try {
    if (profile !== "legacy" && profile !== "explicit_primary") {
      throw new Error("development_profile_invalid");
    }
    const parsed = profile === "explicit_primary"
      ? decodeSolPhotoPrimaryDraft(draft)
      : parseMerianIdentification(draft);
    const name = parsed.scientific_name ?? null;
    diagnostics.declaredResolution = "resolution" in parsed
      ? parsed.resolution
      : null;
    diagnostics.stage = "normalization";
    const normalized = profile === "explicit_primary"
      ? normalizeSolPhotoPrimaryDraft(draft, context)
      : normalizeIdentification(draft, context);
    const value = normalized.identification;
    const after = value.scientific_name ?? null;
    diagnostics.after = flags(after);
    const sanitized = name ? sanitizeScientificName(name) : name;
    diagnostics.sanitizerChanged = sanitized !== name;
    diagnostics.petAliasChanged = !!sanitized &&
      canonicalizeDomesticPetScientificName(
          sanitized,
          parsed.pet_identification,
          parsed.common_name,
        ) !== sanitized;
    diagnostics.nameChanged = name !== after;
    diagnostics.processedMaterialDemoted = normalized.diagnostics.some((d) =>
      d.event === "processed_material_demoted"
    );
    diagnostics.effectiveResolution = "primary" in normalized
      ? normalized.primary.resolution
      : null;
    diagnostics.stage = "taxonomy";
    const subject = value.is_biological_subject
      ? after?.toLowerCase() === "homo sapiens" ? "human" : "biological"
      : "non_biological";
    const named = subject === "biological" && !!after;
    const identity = named
      ? resolveTaxon(taxonomy, after!)
      : { taxon: null, mapping: noIdentityMapping() };
    diagnostics.beforeMapping = parsed.is_biological_subject && name
      ? resolveTaxon(taxonomy, name).mapping
      : noIdentityMapping();
    diagnostics.afterMapping = identity.mapping;
    diagnostics.catalogRank = identity.taxon?.rank ?? null;
    const rank = diagnostics.effectiveResolution;
    diagnostics.rankAgreement = rank === null
      ? "not_declared"
      : !named
      ? "not_applicable"
      : !identity.taxon
      ? "unverified"
      : rank === identity.taxon.rank
      ? "consistent"
      : "conflict";
    if (diagnostics.rankAgreement === "conflict") {
      diagnostics.status = "rank_conflict";
      // Never give a mismatched declared rank credit via catalog coercion.
      return { observation: invalid, diagnostics };
    }
    const observation = parseConfidenceObservation({
      prediction: {
        caseId,
        outcome: "normalized",
        subject,
        resolution: named ? "named" : "unresolved",
        taxon: identity.taxon,
        confidence: value.confidence_score,
      },
      mapping: identity.mapping,
    });
    diagnostics.status = "accepted";
    return { observation, diagnostics };
  } catch {
    return { observation: invalid, diagnostics };
  }
}
