/** A separate content-free projection. Legacy record parsers remain closed. */
import type {
  AIProviderOutcome,
  MultimodalAIRequest,
} from "../../functions/_shared/ai/contracts.ts";
import { SOL_PRIMARY_PROFILE } from "../../functions/_shared/ai/openaiSolPrimary.ts";
import type { PrimaryResolution } from "../../functions/_shared/ai/openaiSolPrimaryContract.ts";
import { normalizeSolPhotoPrimaryDraft } from "../../functions/_shared/ai/openaiSolPrimaryNormalization.ts";
import type { EvaluationInput } from "./contracts.ts";
import type { FactCard } from "./explanationContracts.ts";
import { normalizedExplanationDisplay } from "./explanationReview.ts";
import type { ReviewDisplay } from "./explanationView.ts";
import type { PhotoModelPricing } from "./photoModelContracts.ts";
import {
  initializePhotoModelRecord,
  parsePhotoModelMeasurementRecord,
  type PhotoModelMeasurementRecord,
  projectMeasuredPhotoModelOutcome,
} from "./photoModelRecords.ts";
import type { Taxonomy } from "./runContracts.ts";
import { noIdentityMapping, resolveTaxon } from "./taxonomy.ts";
import { member, requireCondition as check } from "./validation.ts";
import {
  primaryBillingAssignment,
  type SolPrimaryAssignment,
} from "./solPhotoPrimaryLivePreparation.ts";

export type SolPrimaryRecord = Omit<PhotoModelMeasurementRecord, "version"> & {
  version: "sol_primary_photo_attempt_v1";
  primaryResolution: PrimaryResolution | null;
  resolutionOrigin: "explicit" | "catalog" | "structural" | "unknown";
};
const resolutions = [
  "species",
  "genus",
  "family",
  "unresolved_biological",
  "non_biological",
] as const;
export function parseSolPrimaryRecord(
  value: unknown,
  a: SolPrimaryAssignment,
  runDigest: string,
  assignmentDigest: string,
): SolPrimaryRecord {
  // Let the historical parser validate the unchanged accounting and prediction fields.
  check(value !== null && typeof value === "object" && !Array.isArray(value));
  const { version, primaryResolution, resolutionOrigin, ...base } =
    value as Record<string, unknown>;
  check(version === "sol_primary_photo_attempt_v1");
  member(primaryResolution, [null, ...resolutions]);
  member(resolutionOrigin, ["explicit", "catalog", "structural", "unknown"]);
  const record = parsePhotoModelMeasurementRecord(
    { ...base, version: "photo_model_attempt_v2" },
    primaryBillingAssignment(a),
    runDigest,
    assignmentDigest,
  );
  const p = record.prediction;
  if (p.outcome !== "normalized") {
    check(primaryResolution === null && resolutionOrigin === "unknown");
  } else if (a.profile === SOL_PRIMARY_PROFILE) {
    check(resolutionOrigin === "explicit" && primaryResolution !== null);
    if (primaryResolution === "non_biological") {
      check(p.subject === "non_biological" && p.resolution === "unresolved");
    } else if (primaryResolution === "unresolved_biological") {
      check(p.subject === "biological" && p.resolution === "unresolved");
    } else {
      check(p.subject === "biological" || p.subject === "human");
      check(p.resolution === "named");
      // Rank conflicts are invalid normalized results, never silently reinterpreted.
      if (p.taxon) check(p.taxon.rank === primaryResolution);
    }
  } else if (p.resolution === "named") {
    const known = p.taxon &&
      ["species", "genus", "family"].includes(p.taxon.rank);
    check(
      known
        ? resolutionOrigin === "catalog" && primaryResolution === p.taxon!.rank
        : resolutionOrigin === "unknown" && primaryResolution === null,
    );
  } else {
    check(
      resolutionOrigin === "structural" && primaryResolution ===
          (p.subject === "non_biological"
            ? "non_biological"
            : "unresolved_biological"),
    );
  }
  return {
    ...record,
    version,
    primaryResolution,
    resolutionOrigin,
  } as SolPrimaryRecord;
}
export function projectSolPrimaryOutcome(
  outcome: AIProviderOutcome,
  input: EvaluationInput,
  request: MultimodalAIRequest,
  card: FactCard,
  a: SolPrimaryAssignment,
  runDigest: string,
  assignmentDigest: string,
  taxonomy: Taxonomy,
  pricing: PhotoModelPricing,
): { record: SolPrimaryRecord; display: ReviewDisplay | null } {
  check(taxonomy.version === "evaluation_taxonomy_v2");
  const billing = primaryBillingAssignment(a);
  if (a.profile !== SOL_PRIMARY_PROFILE) {
    const { record, display } = projectMeasuredPhotoModelOutcome(
      outcome,
      input,
      request,
      card,
      billing,
      runDigest,
      assignmentDigest,
      taxonomy,
      pricing,
    );
    const p = record.prediction;
    let primaryResolution: PrimaryResolution | null = null;
    let resolutionOrigin: SolPrimaryRecord["resolutionOrigin"] = "unknown";
    if (p.outcome === "normalized") {
      if (p.resolution === "unresolved") {
        primaryResolution = p.subject === "non_biological"
          ? "non_biological"
          : "unresolved_biological";
        resolutionOrigin = "structural";
      } else if (
        p.taxon && ["species", "genus", "family"].includes(p.taxon.rank)
      ) {
        primaryResolution = p.taxon.rank as PrimaryResolution;
        resolutionOrigin = "catalog";
      }
    }
    return {
      record: parseSolPrimaryRecord(
        {
          ...record,
          version: "sol_primary_photo_attempt_v1",
          primaryResolution,
          resolutionOrigin,
        },
        a,
        runDigest,
        assignmentDigest,
      ),
      display,
    };
  }
  const record = {
    ...initializePhotoModelRecord(
      outcome,
      billing,
      runDigest,
      assignmentDigest,
      pricing,
    ),
    version: "sol_primary_photo_attempt_v1" as const,
    mapping: noIdentityMapping(),
    primaryResolution: null as PrimaryResolution | null,
    resolutionOrigin: "unknown" as SolPrimaryRecord["resolutionOrigin"],
  };
  let display: ReviewDisplay | null = null;
  if (outcome.kind === "draft") {
    if (record.returnedModel !== a.model) record.reason = "model_mismatch";
    else if (record.safety !== "allowed") record.reason = "safety_unavailable";
    else {
      const start = performance.now();
      try {
        check(
          input.inputGroup === "photos" &&
            input.assets.every((asset) => asset.kind === "image"),
        );
        const normalized = normalizeSolPhotoPrimaryDraft(outcome.draft, {
          hasVisualEvidence: true,
          hasAudioEvidence: false,
          hasInvasiveLocationContext: false,
          confidencePolicy: { kind: "unqualified" },
        });
        const { primary, identification: v } = normalized;
        const named = ["species", "genus", "family"].includes(
          primary.resolution,
        );
        const identity = named
          ? resolveTaxon(taxonomy, primary.scientific_name!)
          : { taxon: null, mapping: noIdentityMapping() };
        check(!identity.taxon || identity.taxon.rank === primary.resolution);
        record.prediction = {
          caseId: a.caseId,
          outcome: "normalized",
          subject: primary.resolution === "non_biological"
            ? "non_biological"
            : v.scientific_name?.toLowerCase() === "homo sapiens"
            ? "human"
            : "biological",
          resolution: named ? "named" : "unresolved",
          taxon: identity.taxon,
          confidence: v.confidence_score ?? 0,
        };
        record.mapping = identity.mapping;
        record.primaryResolution = primary.resolution;
        record.resolutionOrigin = "explicit";
        record.normalizationMs = Math.max(0, performance.now() - start);
        display = normalizedExplanationDisplay(normalized, request, card);
        if (display) {
          display.decision.push(`Primary resolution: ${primary.resolution}`);
        }
        if (record.estimatedUpperNanoUsd === null) {
          record.reason = "usage_missing";
        }
      } catch {
        record.reason = "normalization_failed";
        record.prediction = { caseId: a.caseId, outcome: "invalid_output" };
        record.mapping = noIdentityMapping();
        record.primaryResolution = null;
        record.resolutionOrigin = "unknown";
        record.normalizationMs = null;
        display = null;
      }
    }
  }
  return {
    record: parseSolPrimaryRecord(record, a, runDigest, assignmentDigest),
    display,
  };
}
