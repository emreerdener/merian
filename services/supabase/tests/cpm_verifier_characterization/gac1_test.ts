import { assert, assertEquals, assertThrows } from "@std/assert";
import { GAC1 } from "./gac1.ts";
import { MiB } from "./policy.ts";
import { createHandler, requestFor } from "./handler.ts";
import {
  CAPABILITY,
  config,
  fixtureResponse,
  ManualClock,
  MEMORY,
} from "./test_support.ts";

function evaluate(a: number[], b: number[], peak = 80) {
  const g = new GAC1();
  g.add(1, 10 * MiB, peak * MiB);
  g.add(2, 10 * MiB, peak * MiB);
  let ack;
  for (const [i, q] of [...a, ...b].entries()) {
    ack = g.add(i + 3, q * MiB, peak * MiB);
    if (ack.decision !== "pending") break;
  }
  return ack!;
}
Deno.test("GAC-1 fixed comparisons, equal threshold and masking hold", () => {
  assertEquals(evaluate(Array(9).fill(20), Array(9).fill(20)).decision, "pass");
  assertEquals(
    evaluate([20, 20, 20, 22, 23, 24, 28, 28, 28], []).decision,
    "drift_failure",
  );
  assertEquals(
    evaluate([20, 20, 20, 21, 20, 22, 20, 20, 28], []).decision,
    "drift_failure",
  );
  assertEquals(
    evaluate(Array(9).fill(20), Array(9).fill(28)).decision,
    "cross_cohort_envelope_review_hold",
  );
  assertEquals(
    evaluate([20, 20, 20, 70, 24, 25, 27, 27, 27], [
      27,
      27,
      27,
      30,
      31,
      32,
      34,
      34,
      34,
    ]).decision,
    "cross_cohort_endpoint_review_hold",
  );
  assertEquals(
    evaluate(Array(9).fill(20), [28, 28, 28, 29, 30, 32, 36, 36, 36]).decision,
    "drift_failure",
  );
});
Deno.test("GAC-1 preserves old warning without terminating and fails invalid sequences", () => {
  const g = new GAC1();
  for (let i = 1; i <= 4; i++) {
    const ack = g.add(i, (10 + i * 3) * MiB, 40 * MiB);
    assertEquals(ack.warning, i === 4);
    assertEquals(ack.decision, "pending");
  }
  assertThrows(() => g.add(6, 20 * MiB, 40 * MiB));
  assertThrows(() => g.add(5, NaN, 40 * MiB));
  assertThrows(() => g.add(5, 40 * MiB, 20 * MiB));
  assertThrows(() => g.add(5, 20 * MiB, 96 * MiB));
  assert(g.accepts(5));
  assertEquals(g.add(5, 20 * MiB, 40 * MiB).decision, "pending");
});
Deno.test("GAC-1 handler opts in, closes ownership, rejects skipped case before GET", async () => {
  const clock = new ManualClock(), cfg = config(clock);
  let gets = 0;
  const handler = createHandler({ ...cfg, growthContract: "GAC-1" }, {
    clock,
    memory: () => MEMORY,
    authenticate: () => Promise.resolve(cfg.operator),
    get: (id) => {
      gets++;
      return Promise.resolve(fixtureResponse(id));
    },
  });
  const ack = await (await handler.handle(requestFor(cfg.run, 1, CAPABILITY)))
    .json();
  assertEquals(ack.version, 2);
  assertEquals(ack.growth, {
    contract: "GAC-1",
    warning: false,
    decision: "pending",
  });
  assert(ack.closed && ack.cleanup && ack.outcome === "verified");
  const skipped = await handler.handle(requestFor(cfg.run, 3, CAPABILITY));
  assertEquals(skipped.status, 409);
  await skipped.body?.cancel();
  assertEquals(gets, 1);
  assertEquals(clock.active, 0);
});
