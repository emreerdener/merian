/** Owner-private history protocol. No operation here authorizes a database write. */
export const HISTORY_VERSION = 1;
export const HISTORY_READER_PROTOCOL = 8;
export const HISTORY_PAGE_SIZE = 20;
export const HISTORY_MAX_REVISION = 2_147_483_646;
export const HISTORY_MAX_RESULT_BYTES = 1_048_576;
export const HISTORY_MAX_CONTEXT_BYTES = 262_144;

export type HistoryErrorCode =
  | "invalid_analysis_history"
  | "analysis_history_not_found"
  | "analysis_history_revision_conflict"
  | "analysis_history_operation_conflict"
  | "analysis_history_deleted"
  | "analysis_history_unavailable"
  | "analysis_history_evidence_unavailable"
  | "analysis_history_evidence_bound"
  | "analysis_history_reader_upgrade_required"
  | "legacy_observation_delete_requires_upgrade"
  | "chat_context_not_replayable";

export class HistoryError extends Error {
  constructor(readonly code: HistoryErrorCode) {
    super(code);
    this.name = "HistoryError";
  }
}

export function invalidHistory(): never {
  throw new HistoryError("invalid_analysis_history");
}

export function exactObject(
  value: unknown,
  keys: readonly string[],
): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  const row = value as Record<string, unknown>;
  if (
    Object.keys(row).length !== keys.length ||
    keys.some((key) => !Object.hasOwn(row, key))
  ) return invalidHistory();
  return row;
}

export function historyUUID(value: unknown): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(
      value,
    )
  ) return invalidHistory();
  return value;
}

export function historyRevision(value: unknown): number {
  if (
    typeof value !== "number" || !Number.isInteger(value) || value < 0 ||
    value > HISTORY_MAX_REVISION
  ) return invalidHistory();
  return value;
}

export function advanceHistoryRevision(value: number): number {
  historyRevision(value);
  if (value === HISTORY_MAX_REVISION) {
    throw new HistoryError("analysis_history_unavailable");
  }
  return value + 1;
}

export interface SelectionRequest {
  schema_version: 1;
  observation_id: string;
  analysis_id: string;
  operation_id: string;
  expected_observation_revision: number;
  expected_review_revision: number;
}

export function parseSelectionRequest(value: unknown): SelectionRequest {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "operation_id",
    "expected_observation_revision",
    "expected_review_revision",
  ]);
  if (row.schema_version !== HISTORY_VERSION) return invalidHistory();
  return Object.freeze({
    schema_version: HISTORY_VERSION,
    observation_id: historyUUID(row.observation_id),
    analysis_id: historyUUID(row.analysis_id),
    operation_id: historyUUID(row.operation_id),
    expected_observation_revision: historyRevision(
      row.expected_observation_revision,
    ),
    expected_review_revision: historyRevision(row.expected_review_revision),
  });
}

/** The whole expected state is part of idempotency, not just the target result. */
export function selectionIdentity(request: SelectionRequest): string {
  return JSON.stringify(parseSelectionRequest(request));
}

export interface HistoryPageRequest {
  schema_version: 1;
  observation_id: string;
  before_ordinal: number | null;
  limit: number;
}

export function parseHistoryPageRequest(value: unknown): HistoryPageRequest {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "before_ordinal",
    "limit",
  ]);
  if (row.schema_version !== HISTORY_VERSION) return invalidHistory();
  const limit = historyRevision(row.limit);
  const before = row.before_ordinal === null
    ? null
    : historyRevision(row.before_ordinal);
  if (limit < 1 || limit > HISTORY_PAGE_SIZE || before === 0) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: HISTORY_VERSION,
    observation_id: historyUUID(row.observation_id),
    before_ordinal: before,
    limit,
  });
}

export interface AnalysisIdentity {
  schema_version: 1;
  observation_id: string;
  analysis_id: string;
  source_analysis_id: string | null;
  request_digest: string;
}

export function parseAnalysisIdentity(value: unknown): AnalysisIdentity {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "source_analysis_id",
    "request_digest",
  ]);
  if (
    row.schema_version !== HISTORY_VERSION ||
    typeof row.request_digest !== "string" ||
    !/^[0-9a-f]{64}$/.test(row.request_digest)
  ) return invalidHistory();
  const analysis = historyUUID(row.analysis_id);
  const observation = historyUUID(row.observation_id);
  const source = row.source_analysis_id === null
    ? null
    : historyUUID(row.source_analysis_id);
  if (
    analysis === source || analysis === observation || source === observation
  ) {
    return invalidHistory();
  }
  return Object.freeze({
    schema_version: HISTORY_VERSION,
    observation_id: observation,
    analysis_id: analysis,
    source_analysis_id: source,
    request_digest: row.request_digest,
  });
}

export interface AdmittedChatContext {
  schema_version: 1;
  observation_id: string;
  analysis_id: string;
  observation_revision: number;
  review_revision: number;
  client_message_id: string;
  context_version: string;
  configuration_version: string;
  system_instruction: string;
  user_prompt: string;
}

/** Persist with message admission; dispatch must use the returned stored value. */
export function parseAdmittedChatContext(value: unknown): AdmittedChatContext {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "observation_revision",
    "review_revision",
    "client_message_id",
    "context_version",
    "configuration_version",
    "system_instruction",
    "user_prompt",
  ]);
  if (row.schema_version !== HISTORY_VERSION) return invalidHistory();
  for (const field of ["context_version", "configuration_version"] as const) {
    if (
      typeof row[field] !== "string" ||
      !/^[a-zA-Z0-9_.:-]{1,128}$/.test(row[field])
    ) return invalidHistory();
  }
  if (
    typeof row.system_instruction !== "string" ||
    typeof row.user_prompt !== "string" || row.system_instruction.length < 1 ||
    row.user_prompt.length < 1
  ) return invalidHistory();
  const encoder = new TextEncoder();
  if (
    encoder.encode(row.system_instruction).length > 65_536 ||
    encoder.encode(row.user_prompt).length > 131_072 ||
    encoder.encode(JSON.stringify(row)).length > HISTORY_MAX_CONTEXT_BYTES
  ) return invalidHistory();
  return Object.freeze({
    schema_version: HISTORY_VERSION,
    observation_id: historyUUID(row.observation_id),
    analysis_id: historyUUID(row.analysis_id),
    observation_revision: historyRevision(row.observation_revision),
    review_revision: historyRevision(row.review_revision),
    client_message_id: historyUUID(row.client_message_id),
    context_version: row.context_version as string,
    configuration_version: row.configuration_version as string,
    system_instruction: row.system_instruction,
    user_prompt: row.user_prompt,
  });
}

/** Immutable terminal outcome, never a source of current identification authority. */
export interface SelectionRejection extends SelectionRequest {
  outcome: "revision_conflict";
}

export function parseSelectionRejection(
  value: unknown,
  request: SelectionRequest,
): SelectionRejection {
  const row = exactObject(value, [
    "schema_version",
    "observation_id",
    "analysis_id",
    "operation_id",
    "expected_observation_revision",
    "expected_review_revision",
    "outcome",
  ]);
  const { outcome, ...identity } = row;
  if (
    outcome !== "revision_conflict" ||
    selectionIdentity(parseSelectionRequest(identity)) !==
      selectionIdentity(request)
  ) {
    return invalidHistory();
  }
  return Object.freeze({ ...parseSelectionRequest(identity), outcome });
}
