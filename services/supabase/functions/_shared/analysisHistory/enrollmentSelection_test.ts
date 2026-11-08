import { assert, assertEquals, assertRejects } from "@std/assert";
import { parseHistoryState } from "./state.ts";
import { HistoryError } from "./contract.ts";
import { parseEnrollmentSelection } from "./enrollmentSelection.ts";
import { enrollmentBaselineDigest } from "./baselineRecovery.ts";

const fixture = (name: string) =>
  Deno.readTextFile(new URL(`./fixtures/${name}.json`, import.meta.url)).then(
    JSON.parse,
  );
const state = await fixture("state-v1");
const association = await fixture("baseline-recovery-v1");
const page = await fixture("page-v1");
const later = "00000000-0000-4000-8000-000000000009";
const laterSnapshot = JSON.stringify({
  ...JSON.parse(page.items[0].snapshot),
  analysis_id: later,
  ordinal: 2,
});
const baseline = {
  ...state,
  state_revision: 8,
  selected_analysis_id: later,
  analysis: { ...state.analysis, snapshot: association.snapshot },
};
const selected = {
  ...state,
  state_revision: 8,
  selected_analysis_id: later,
  analysis: { ...state.analysis, snapshot: laterSnapshot },
};
const pair = {
  schema_version: 1,
  baseline_sha256: association.snapshot_sha256,
  baseline_state: baseline,
  selected_state: selected,
};
const parse = (value: unknown) =>
  parseEnrollmentSelection(
    value,
    state.observation_id,
    state.owner_id,
    association.baseline_analysis_id,
  );

Deno.test("enrollment selection binds original V3 and later selected result at one revision", async () => {
  assertEquals(pair, await fixture("enrollment-selection-v1"));
  assertEquals(await parse(pair), pair);
  const same = {
    ...baseline,
    selected_analysis_id: association.baseline_analysis_id,
  };
  const unchanged = { ...pair, baseline_state: same, selected_state: same };
  assertEquals(await parse(unchanged), unchanged);
  const text = association.snapshot + "\n";
  const exact = {
    ...pair,
    baseline_sha256: await enrollmentBaselineDigest(text),
    baseline_state: {
      ...baseline,
      analysis: { ...baseline.analysis, snapshot: text },
    },
  };
  assertEquals((await parse(exact)).baseline_state.analysis.snapshot, text);
});

Deno.test("enrollment selection rejects mixed authority, forged baseline and combined oversize", async () => {
  const candidates = [
    { ...pair, schema_version: 2 },
    { ...pair, original_intent: later },
    { ...pair, baseline_sha256: "0".repeat(64) },
    { ...pair, selected_state: { ...selected, state_revision: 9 } },
    {
      ...pair,
      baseline_state: {
        ...baseline,
        selected_analysis_id: association.baseline_analysis_id,
      },
    },
    { ...pair, selected_state: { ...selected, owner_id: later } },
    { ...pair, selected_state: { ...selected, observation_id: later } },
    { ...pair, selected_state: { ...selected, analysis: baseline.analysis } },
    { ...pair, baseline_state: { ...baseline, analysis: selected.analysis } },
    {
      ...pair,
      selected_state: {
        ...selected,
        analysis: { ...selected.analysis, snapshot: " ".repeat(4194304) },
      },
    },
  ];
  for (const candidate of candidates) {
    await assertRejects(() => parse(candidate), HistoryError);
  }
  await assertRejects(
    () =>
      parseEnrollmentSelection(
        pair,
        state.observation_id,
        state.owner_id,
        later,
      ),
    HistoryError,
  );
  const same = {
    ...baseline,
    selected_analysis_id: association.baseline_analysis_id,
  };
  await assertRejects(
    () =>
      parse({
        ...pair,
        baseline_state: same,
        selected_state: {
          ...same,
          analysis: { ...same.analysis, review_revision: 1 },
        },
      }),
    HistoryError,
  );
});

Deno.test("enrollment pair preserves selected audio4 and video5 with reader11", async () => {
  for (const vector of await fixture("enrollment-selection-media-v1")) {
    const actual = await parse(vector.pair);
    assertEquals(actual, vector.pair, vector.media);
    assertEquals(
      JSON.parse(actual.selected_state.analysis.snapshot).schema_version,
      vector.version,
    );
  }
});

Deno.test("combined pair cap rejects individually valid bounded states", async () => {
  const large = structuredClone(pair);
  for (const item of [large.baseline_state, large.selected_state]) {
    const text = item.analysis.snapshot;
    item.analysis.snapshot = text +
      "\t".repeat(1048576 - new TextEncoder().encode(text).length);
    item.analysis.review_snapshot.user_identification_override = "\u0001"
      .repeat(1024);
  }
  large.baseline_sha256 = await enrollmentBaselineDigest(
    large.baseline_state.analysis.snapshot,
  );
  for (
    const [item, analysis_id] of [[
      large.baseline_state,
      association.baseline_analysis_id,
    ], [large.selected_state, null]] as const
  ) {
    assertEquals(
      parseHistoryState(
        item,
        {
          schema_version: 1,
          observation_id: state.observation_id,
          analysis_id,
        },
        state.owner_id,
        11,
      ),
      item,
    );
    assert(new TextEncoder().encode(JSON.stringify(item)).length < 4194304);
  }
  assert(new TextEncoder().encode(JSON.stringify(large)).length > 4194304);
  await assertRejects(() => parse(large), HistoryError);
});
