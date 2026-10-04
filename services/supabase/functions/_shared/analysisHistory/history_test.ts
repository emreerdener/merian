import { assertEquals, assertThrows } from "@std/assert";
import {
  advanceHistoryRevision,
  HISTORY_MAX_REVISION,
  HistoryError,
  parseAdmittedChatContext,
  parseAnalysisIdentity,
  parseHistoryPageRequest,
  parseSelectionRejection,
  parseSelectionRequest,
  type SelectionRequest,
} from "./contract.ts";
import {
  advanceAuthority,
  canApplyReconciliation,
  initializeSelection,
  type ObservationSelection,
  selectAnalysis,
} from "./transitions.ts";

const observation = "00000000-0000-4000-8000-000000000001";
const a = "00000000-0000-4000-8000-000000000002";
const b = "00000000-0000-4000-8000-000000000003";
const operation = "00000000-0000-4000-8000-000000000004";
const nextOperation = "00000000-0000-4000-8000-000000000005";
const authority = (analysis_id = a, review_revision = 0) => ({
  observation_id: observation,
  analysis_id,
  review_revision,
});
const initial = (): ObservationSelection => ({
  observation_id: observation,
  selected_analysis_id: a,
  initialized: true,
  revision: 10,
  deleted: false,
});
const request = (
  analysis_id = b,
  expected_observation_revision = 10,
  operation_id = operation,
): SelectionRequest => ({
  schema_version: 1 as const,
  observation_id: observation,
  analysis_id,
  operation_id,
  expected_observation_revision,
  expected_review_revision: 0,
});

Deno.test("selection rejects forged owner fields, unsupported versions and invalid revisions", () => {
  for (
    const invalid of [
      { ...request(), owner_id: observation },
      { ...request(), schema_version: 2 },
      { ...request(), expected_observation_revision: 1.5 },
      { ...request(), expected_review_revision: -1 },
      { ...request(), analysis_id: "bad" },
      { ...request(), expected_review_revision: HISTORY_MAX_REVISION + 1 },
    ]
  ) assertThrows(() => parseSelectionRequest(invalid), HistoryError);
  assertEquals(parseSelectionRequest(request()), request());
});

Deno.test("analysis identity is stable across transport attempts and binds source and digest", () => {
  const input = {
    schema_version: 1 as const,
    observation_id: observation,
    analysis_id: b,
    source_analysis_id: a,
    request_digest: "a".repeat(64),
  };
  assertEquals(parseAnalysisIdentity(input), input);
  assertThrows(
    () => parseAnalysisIdentity({ ...input, source_analysis_id: b }),
    HistoryError,
  );
  assertThrows(
    () => parseAnalysisIdentity({ ...input, source_analysis_id: observation }),
    HistoryError,
  );
  assertThrows(
    () => parseAnalysisIdentity({ ...input, analysis_id: observation }),
    HistoryError,
  );
  assertThrows(
    () => parseAnalysisIdentity({ ...input, request_digest: "invalid" }),
    HistoryError,
  );
  assertThrows(
    () => parseAnalysisIdentity({ ...input, provider_attempt_id: operation }),
    HistoryError,
  );
});

Deno.test("history pages have bounded keyset cursors rather than unbounded result arrays", () => {
  const input = {
    schema_version: 1 as const,
    observation_id: observation,
    before_ordinal: null,
    limit: 20,
  };
  assertEquals(parseHistoryPageRequest(input), input);
  for (const limit of [0, 21, Infinity, 0.5]) {
    assertThrows(
      () => parseHistoryPageRequest({ ...input, limit }),
      HistoryError,
    );
  }
  assertThrows(
    () => parseHistoryPageRequest({ ...input, before_ordinal: 0 }),
    HistoryError,
  );
});

Deno.test("first completion initializes once; later completions append without selecting", () => {
  const empty = {
    ...initial(),
    initialized: false,
    selected_analysis_id: null,
    revision: 0,
  };
  const selected = initializeSelection(empty, authority());
  assertEquals(selected.selected_analysis_id, a);
  assertEquals(selected.revision, 1);
  assertEquals(initializeSelection(selected, authority(b)), selected);
  assertEquals(initializeSelection(initial(), authority(b)), initial());
});

Deno.test("selection does not change either analysis review authority", () => {
  const target = Object.freeze(authority(b));
  const result = selectAnalysis(initial(), target, request(), null);
  assertEquals(result.state.selected_analysis_id, b);
  assertEquals(result.state.revision, 11);
  assertEquals(target, authority(b));
  assertEquals(result.recorded.receipt.previous_analysis_id, a);
});

Deno.test("lost acknowledgement replay returns original receipt without rolling current state back", () => {
  const selected = selectAnalysis(initial(), authority(b), request(), null);
  const restored = selectAnalysis(
    selected.state,
    authority(a),
    request(a, 11, nextOperation),
    null,
  );
  const replay = selectAnalysis(
    restored.state,
    authority(b),
    request(),
    selected.recorded,
  );
  assertEquals(replay.replay, true);
  assertEquals(replay.recorded, selected.recorded);
  assertEquals(replay.state, restored.state);
  assertThrows(
    () =>
      selectAnalysis(
        restored.state,
        authority(a),
        request(a),
        selected.recorded,
      ),
    HistoryError,
    "analysis_history_operation_conflict",
  );
});

Deno.test("authority changes fence stale selection including non-selected published analysis", () => {
  const changed = advanceAuthority(initial());
  assertThrows(
    () => selectAnalysis(changed, authority(b), request(), null),
    HistoryError,
    "analysis_history_revision_conflict",
  );
  assertThrows(
    () => selectAnalysis(initial(), authority(b, 1), request(), null),
    HistoryError,
    "analysis_history_revision_conflict",
  );
});

Deno.test("A to B to A and reordered reconciliation cannot resurrect older credit", () => {
  const selected = selectAnalysis(initial(), authority(b), request(), null);
  const restored = selectAnalysis(
    selected.state,
    authority(a),
    request(a, 11, nextOperation),
    null,
  );
  let applied = 9;
  const effects: number[] = [];
  for (const revision of [11, 12, 10, 11, 12]) {
    if (canApplyReconciliation(restored.state, revision, applied)) {
      applied = revision;
      effects.push(revision);
    }
  }
  assertEquals(effects, [12]);
  assertEquals(restored.state.selected_analysis_id, a);
  assertEquals(restored.state.revision, 12);
});

Deno.test("stale Undo is a conditional selection, not an overwrite", () => {
  const selected = selectAnalysis(initial(), authority(b), request(), null);
  const newer = advanceAuthority(selected.state);
  assertThrows(
    () =>
      selectAnalysis(newer, authority(a), request(a, 11, nextOperation), null),
    HistoryError,
    "analysis_history_revision_conflict",
  );
});

Deno.test("deletion wins over first completion, selection, authority changes and recorded replay", () => {
  const recorded =
    selectAnalysis(initial(), authority(b), request(), null).recorded;
  const deleted = { ...initial(), deleted: true };
  assertThrows(
    () => initializeSelection(deleted, authority()),
    HistoryError,
    "analysis_history_deleted",
  );
  assertThrows(
    () => selectAnalysis(deleted, authority(b), request(), recorded),
    HistoryError,
    "analysis_history_deleted",
  );
  assertThrows(
    () => advanceAuthority(deleted),
    HistoryError,
    "analysis_history_deleted",
  );
  assertEquals(canApplyReconciliation(deleted, 10, 9), false);
});

Deno.test("cross-observation result never changes selection", () => {
  assertThrows(
    () =>
      selectAnalysis(
        initial(),
        { ...authority(b), observation_id: nextOperation },
        request(),
        null,
      ),
    HistoryError,
    "analysis_history_not_found",
  );
});

Deno.test("revision exhaustion fails closed rather than wrapping an ABA fence", () => {
  assertThrows(
    () => advanceHistoryRevision(HISTORY_MAX_REVISION),
    HistoryError,
    "analysis_history_unavailable",
  );
});

Deno.test("admitted chat context captures immutable inputs and enforces byte bounds", () => {
  const input = {
    schema_version: 1 as const,
    observation_id: observation,
    analysis_id: a,
    observation_revision: 10,
    review_revision: 0,
    client_message_id: operation,
    context_version: "history.v1",
    configuration_version: "prompt.v1",
    system_instruction: "Synthetic identification context.",
    user_prompt: "Synthetic prior turns and question.",
  };
  const snapshot = parseAdmittedChatContext(input);
  input.system_instruction = "A later context must not replace admission.";
  assertEquals(
    snapshot.system_instruction,
    "Synthetic identification context.",
  );
  assertEquals(Object.isFrozen(snapshot), true);
  assertThrows(
    () =>
      parseAdmittedChatContext({ ...input, user_prompt: "🦋".repeat(32_769) }),
    HistoryError,
  );
  assertThrows(
    () => parseAdmittedChatContext({ ...input, context_version: "" }),
    HistoryError,
  );
});

Deno.test("native durable selection fixture matches the canonical request and receipt", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/selection-v1.json", import.meta.url),
    ),
  );
  const parsed = parseSelectionRequest(fixture.request);
  assertEquals(parsed, fixture.request);
  const selected = selectAnalysis(
    initial(),
    authority(parsed.analysis_id, parsed.expected_review_revision),
    parsed,
    null,
  );
  assertEquals(selected.recorded.receipt, fixture.receipt);
  const newer = { ...selected.state, selected_analysis_id: a, revision: 12 };
  const replayed = selectAnalysis(
    newer,
    authority(parsed.analysis_id),
    parsed,
    selected.recorded,
  );
  assertEquals(replayed.state, newer);
  assertEquals(replayed.recorded.receipt, fixture.receipt);
});

Deno.test("durable selection rejection binds every request field and rejects extra authority", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/selection-v1.json", import.meta.url),
    ),
  );
  assertEquals(
    parseSelectionRejection(fixture.rejection, fixture.request),
    fixture.rejection,
  );
  for (
    const [key, value] of Object.entries({
      schema_version: 2,
      observation_id: a,
      analysis_id: a,
      operation_id: a,
      expected_observation_revision: 11,
      expected_review_revision: 1,
      outcome: "unavailable",
      authority: {},
    })
  ) {
    assertThrows(
      () =>
        parseSelectionRejection(
          { ...fixture.rejection, [key]: value },
          fixture.request,
        ),
      HistoryError,
    );
  }
});
