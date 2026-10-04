import { parseAIIdentificationReview } from "../identify/aiIdentificationReview.ts";
import { parseSpeciesReview } from "../identify/speciesReview.ts";
import {
  exactObject,
  historyRevision,
  historyUUID,
  invalidHistory,
} from "./contract.ts";
import { decodeAnalysisResultSnapshot } from "./result.ts";

export function parseHistoryStateRequest(value: unknown) {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
  ]);
  if (row.schema_version !== 1) return invalidHistory();
  const observation = historyUUID(row.observation_id);
  const analysis = row.analysis_id === null
    ? null
    : historyUUID(row.analysis_id);
  if (analysis === observation) return invalidHistory();
  return {
    schema_version: 1 as const,
    observation_id: observation,
    analysis_id: analysis,
  };
}
export type HistoryStateRequest = ReturnType<typeof parseHistoryStateRequest>;

/** Mutable authority is independently bounded; never write it into result bytes. */
export function parseHistoryReview(value: unknown) {
  const row = exactObject(value, [
    "ai_identification_review",
    "confirmed_species_identity",
    "confirmed_species_identity_revision",
    "confirmed_species_id",
    "user_identification_override",
    "user_confirmed_identification",
    "user_review_state",
  ]);
  if (new TextEncoder().encode(JSON.stringify(row)).length > 32768) {
    return invalidHistory();
  }
  try {
    const ai = row.ai_identification_review === null
      ? null
      : parseAIIdentificationReview(row.ai_identification_review);
    const revision = row.confirmed_species_identity_revision;
    if (
      typeof revision !== "number" || !Number.isInteger(revision) ||
      revision < 0 || revision > 2147483647
    ) return invalidHistory();
    const confirmed = row.confirmed_species_id === null
      ? null
      : historyUUID(row.confirmed_species_id);
    const override = row.user_identification_override;
    const selected = row.user_confirmed_identification;
    const state = row.user_review_state;
    if (
      (override !== null &&
        (typeof override !== "string" ||
          new TextEncoder().encode(override).length > 1024)) ||
      (selected !== null && typeof selected !== "boolean") ||
      (state !== null &&
        (typeof state !== "string" ||
          !["unreviewed", "ai_confirmed", "user_overridden"].includes(state)))
    ) return invalidHistory();
    // Legacy saved fields may predate verified identity. Preserve them verbatim;
    // an explicit identity, when present, must satisfy its complete contract.
    const identity = row.confirmed_species_identity === null
      ? null
      : parseSpeciesReview({
        version: 1,
        revision,
        identity: row.confirmed_species_identity,
        confirmed_species_id: confirmed,
        user_identification_override: override,
        user_confirmed_identification: selected,
        user_review_state: state,
      }).identity;
    return {
      ai_identification_review: ai,
      confirmed_species_identity: identity,
      confirmed_species_identity_revision: revision,
      confirmed_species_id: confirmed,
      user_identification_override: override,
      user_confirmed_identification: selected,
      user_review_state: state,
    };
  } catch {
    return invalidHistory();
  }
}

/** Null-target reads bind to selection; explicit targets are previews only. */
export function parseHistoryState(
  value: unknown,
  request: HistoryStateRequest,
  ownerID: string,
) {
  const expected = parseHistoryStateRequest(request);
  const row = exactObject(value, [
    "schema_version",
    "owner_id",
    "observation_id",
    "state_revision",
    "selection_initialized",
    "selected_analysis_id",
    "analysis",
  ]);
  if (
    new TextEncoder().encode(JSON.stringify(row)).length > 4194304 ||
    row.schema_version !== 1 ||
    historyUUID(row.owner_id) !== historyUUID(ownerID) ||
    historyUUID(row.observation_id) !== expected.observation_id ||
    row.selection_initialized !== true
  ) return invalidHistory();
  const revision = historyRevision(row.state_revision);
  const selected = historyUUID(row.selected_analysis_id);
  if (revision < 1 || selected === expected.observation_id) {
    return invalidHistory();
  }
  const item = exactObject(row.analysis, [
    "snapshot",
    "review_revision",
    "review_snapshot",
  ]);
  const result = decodeAnalysisResultSnapshot(item.snapshot, 9);
  if (
    result.observation_id !== expected.observation_id ||
    result.analysis_id !== (expected.analysis_id ?? selected)
  ) return invalidHistory();
  return {
    schema_version: 1 as const,
    owner_id: ownerID,
    observation_id: expected.observation_id,
    state_revision: revision,
    selection_initialized: true as const,
    selected_analysis_id: selected,
    analysis: {
      snapshot: item.snapshot as string,
      review_revision: historyRevision(item.review_revision),
      review_snapshot: parseHistoryReview(item.review_snapshot),
    },
  };
}
