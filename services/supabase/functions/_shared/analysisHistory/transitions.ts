import {
  advanceHistoryRevision,
  HistoryError,
  selectionIdentity,
  type SelectionRequest,
} from "./contract.ts";

export interface ObservationSelection {
  observation_id: string;
  selected_analysis_id: string | null;
  initialized: boolean;
  revision: number;
  deleted: boolean;
}

export interface AnalysisAuthority {
  observation_id: string;
  analysis_id: string;
  review_revision: number;
}

export interface SelectionReceipt {
  schema_version: 1;
  operation_id: string;
  observation_id: string;
  previous_analysis_id: string;
  selected_analysis_id: string;
  observation_revision: number;
  review_revision: number;
}

export interface RecordedSelection {
  identity: string;
  receipt: SelectionReceipt;
}

function requireLive(state: ObservationSelection) {
  if (state.deleted) throw new HistoryError("analysis_history_deleted");
}

/** Pure decisions used inside a locked persistence transaction, never instead of one. */
export function selectAnalysis(
  state: ObservationSelection,
  target: AnalysisAuthority,
  request: SelectionRequest,
  existing: RecordedSelection | null,
): {
  state: ObservationSelection;
  recorded: RecordedSelection;
  replay: boolean;
} {
  requireLive(state);
  const identity = selectionIdentity(request);
  if (
    request.observation_id !== state.observation_id ||
    target.observation_id !== state.observation_id ||
    target.analysis_id !== request.analysis_id
  ) throw new HistoryError("analysis_history_not_found");
  if (existing) {
    if (
      existing.identity !== identity ||
      existing.receipt.operation_id !== request.operation_id ||
      existing.receipt.observation_id !== state.observation_id
    ) throw new HistoryError("analysis_history_operation_conflict");
    // Return an old receipt without installing its old state over current state.
    return { state, recorded: existing, replay: true };
  }
  if (
    !state.initialized || state.selected_analysis_id === null ||
    state.revision !== request.expected_observation_revision ||
    target.review_revision !== request.expected_review_revision
  ) throw new HistoryError("analysis_history_revision_conflict");
  const revision = advanceHistoryRevision(state.revision);
  const receipt: SelectionReceipt = Object.freeze({
    schema_version: 1,
    operation_id: request.operation_id,
    observation_id: state.observation_id,
    previous_analysis_id: state.selected_analysis_id,
    selected_analysis_id: target.analysis_id,
    observation_revision: revision,
    review_revision: target.review_revision,
  });
  return {
    state: { ...state, revision, selected_analysis_id: target.analysis_id },
    recorded: { identity, receipt },
    replay: false,
  };
}

/** Called only after result + required evidence have durably completed. */
export function initializeSelection(
  state: ObservationSelection,
  completed: AnalysisAuthority,
): ObservationSelection {
  requireLive(state);
  if (completed.observation_id !== state.observation_id) {
    throw new HistoryError("analysis_history_not_found");
  }
  if (state.initialized) return state;
  if (state.selected_analysis_id !== null) {
    throw new HistoryError("analysis_history_revision_conflict");
  }
  return {
    ...state,
    initialized: true,
    selected_analysis_id: completed.analysis_id,
    revision: advanceHistoryRevision(state.revision),
  };
}

/** Includes changes to a non-selected result, which may still be published. */
export function advanceAuthority(
  state: ObservationSelection,
): ObservationSelection {
  requireLive(state);
  return { ...state, revision: advanceHistoryRevision(state.revision) };
}

/** Sink must compare/apply this revision in the SAME transaction as its effects. */
export function canApplyReconciliation(
  state: ObservationSelection,
  expectedRevision: number,
  lastAppliedRevision: number,
): boolean {
  return !state.deleted && expectedRevision === state.revision &&
    expectedRevision > lastAppliedRevision;
}
