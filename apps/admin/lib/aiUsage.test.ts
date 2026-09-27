import assert from "node:assert/strict";
import { test } from "node:test";
import { attributionLabel, usageCost } from "./aiUsage.ts";

test("zero usage is distinct from usage with no known price", () => {
  assert.deepEqual(
    usageCost({
      events: 0,
      priced_events: 0,
      unpriced_events: 0,
      estimated_cost_microusd: 0,
    }),
    { value: "$0.00", detail: "No recorded usage" },
  );
  assert.deepEqual(
    usageCost({
      events: 2,
      priced_events: 0,
      unpriced_events: 2,
      estimated_cost_microusd: 0,
    }),
    { value: "Unavailable", detail: "2 events unpriced" },
  );
});
test("a partial sum explains the missing cost; complete estimates include coverage", () => {
  assert.deepEqual(
    usageCost({
      events: 4,
      priced_events: 3,
      unpriced_events: 1,
      estimated_cost_microusd: 1250000,
    }),
    {
      value: "$1.25",
      detail: "3 of 4 events priced · 1 unpriced; total cost unknown",
    },
  );
  assert.deepEqual(
    usageCost({
      events: 3,
      priced_events: 3,
      unpriced_events: 0,
      estimated_cost_microusd: 1250000,
    }),
    { value: "$1.25", detail: "All 3 events priced" },
  );
  assert.equal(
    usageCost({
      events: 1,
      priced_events: 1,
      unpriced_events: 0,
      estimated_cost_microusd: 0,
    }).value,
    "$0.00",
  );
});
test("old backends and malformed coverage fail to unavailable instead of showing a total", () => {
  const valid = {
    events: 1,
    priced_events: 1,
    unpriced_events: 0,
    estimated_cost_microusd: 10,
  };
  for (
    const usage of [
      {},
      { events: 1, estimated_cost_microusd: 0 },
      { ...valid, events: 2 },
      { ...valid, events: -1 },
      { ...valid, priced_events: 0.5 },
      { ...valid, unpriced_events: NaN },
      { ...valid, estimated_cost_microusd: null },
      { ...valid, estimated_cost_microusd: -1 },
      { ...valid, estimated_cost_microusd: Infinity },
      { ...valid, estimated_cost_microusd: Number.MAX_SAFE_INTEGER + 1 },
      { ...valid, priced_events: 0, unpriced_events: 1 },
    ]
  ) {
    assert.deepEqual(usageCost(usage), {
      value: "Unavailable",
      detail: "Pricing coverage unavailable",
    });
  }
});
test("inferred attribution stays visibly separate from recorded execution", () => {
  assert.equal(attributionLabel("saved_result"), "Saved result");
  assert.equal(attributionLabel("legacy_tier"), "Inferred from legacy tier");
  assert.equal(attributionLabel("execution_metadata"), "Execution metadata");
  assert.equal(attributionLabel("legacy_model"), "Inferred from legacy model");
  assert.equal(attributionLabel("unrecognized"), "Unknown");
});
