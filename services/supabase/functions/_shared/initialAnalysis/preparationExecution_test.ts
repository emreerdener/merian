import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { initialPreparationDigest } from "./preparationCandidate.ts";
import { initialMediaContractDigest } from "./mediaPreparationProfile.ts";
import {
  executionDigest,
  preparationContext,
  type PreparationGrant,
  type PreparationOutcome,
  type PreparationOutputReceipt,
  type PreparationResolvedManifest,
  type PreparationSourceReceipt,
  preparationWallMs,
  validateGrant,
  validatePreparationOutcome,
  validatePreparationReply,
  validateSourceReceipt,
} from "./preparationExecutionContract.ts";
import {
  type PreparationExecutionDependencies,
  type PreparationOperation,
  reconcileInitialPreparationOutput,
  runInitialPreparation,
} from "./preparationExecution.ts";
import vectors from "./fixtures/media-lifecycle-v2.json" with { type: "json" };

async function fixture() {
  const vector = structuredClone(vectors.valid[0]);
  const bytes = Uint8Array.from({ length: 68 }, (_, i) => i);
  const sha = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))]
    .map((x) => x.toString(16).padStart(2, "0")).join("");
  vector.candidate.source_plan.sources[0].source_sha256 = sha;
  vector.profile.spec.limits.wall_ms = 200;
  vector.profile.spec.rules[0].limits.wall_ms = 200;
  vector.profile.qualification.spec_digest = await initialMediaContractDigest(
    "profile_spec",
    initialCanonicalText(vector.profile.spec),
  );
  vector.assignment.candidate_digest = await initialPreparationDigest(
    "preparation-candidate",
    initialCanonicalText(vector.candidate),
  );
  vector.assignment.source_plan_digest = await initialMediaContractDigest(
    "source_plan",
    initialCanonicalText(vector.candidate.source_plan),
  );
  vector.assignment.preparation.profile_digest =
    await initialMediaContractDigest(
      "profile",
      initialCanonicalText(vector.profile),
    );
  vector.assignment.preparation.source_mapping[0].source = structuredClone(
    vector.candidate.source_plan.sources[0],
  );
  const input = {
    owner: "00000000-0000-4000-8000-000000001001",
    scan: "00000000-0000-4000-8000-000000001002",
    candidate: vector.candidate,
    assignment: vector.assignment,
    profile: vector.profile,
  };
  const ctx = await preparationContext(
    input.scan,
    input.candidate,
    input.assignment,
    input.profile,
  );
  const initial = performance.now(), base = 1000000, expiry = base + 300000;
  let source: PreparationSourceReceipt | null = null,
    grant: PreparationGrant | null = null,
    output: {
      request: PreparationOutputReceipt;
      resolved: PreparationResolvedManifest;
    } | null = null,
    result: PreparationOutcome | null = null;
  const calls: PreparationOperation[] = [],
    counts = { runtime: 0, reads: 0, retains: 0, issues: 0 };
  const now = () => base + Math.floor(performance.now() - initial);
  const id = {
    version: 1 as const,
    scan_id: input.scan,
    assignment_digest: ctx.assignment_digest,
  };
  let failAfter: PreparationOperation | null = null,
    terminal = false,
    mutate = false;
  const originalBytes = new Uint8Array(bytes);
  const deps: PreparationExecutionDependencies = {
    async call(op, args, _signal) {
      calls.push(op);
      if (terminal) return { version: 1, outcome: "held", reason: "expired" };
      let answer: unknown;
      if (op === "get_initial_preparation_execution_status") {
        return {
          version: 1,
          outcome: "status",
          phase: result
            ? "outcome_ready"
            : output
            ? "output_registered"
            : grant
            ? "issued"
            : source
            ? "verified"
            : "allocated",
          source,
          execution_reference: grant
            ? { grant_id: grant.grant_id, source_digest: grant.source_digest }
            : null,
          output,
          result,
          server_now_ms: now(),
          expires_at_ms: expiry,
        };
      }
      if (op === "settle_initial_preparation_sources") {
        source = JSON.parse(String(args.p_receipt));
        answer = {
          version: 1,
          outcome: "verified",
          receipt: source,
          digest: await executionDigest(
            "source_verification",
            String(args.p_receipt),
          ),
        };
      } else if (op === "issue_initial_preparation_execution") {
        if (grant) {
          return { version: 1, outcome: "held", reason: "preparation_issued" };
        }
        counts.issues++;
        const issued = now(), wall = vector.profile.spec.limits.wall_ms;
        grant = {
          ...id,
          grant_id: "00000000-0000-4000-8000-000000001003",
          source_digest: String(args.p_source_digest),
          profile_digest: ctx.assignment.preparation.profile_digest,
          artifact_digest: vector.profile.spec.artifact.sha256,
          issued_at_ms: issued,
          execution_deadline_ms: issued + 5000 + wall,
          registration_deadline_ms: issued + 10000 + wall,
          outcome_deadline_ms: issued + 45000 + wall,
        };
        answer = {
          version: 1,
          outcome: "granted",
          grant,
          server_now_ms: now(),
          expires_at_ms: expiry,
        };
      } else if (op === "register_initial_preparation_output") {
        const request = JSON.parse(
          String(args.p_manifest),
        ) as PreparationOutputReceipt;
        const resolved: PreparationResolvedManifest = {
          ...id,
          grant_id: grant!.grant_id,
          request_digest: await executionDigest(
            "output_manifest",
            String(args.p_manifest),
          ),
          entries: [{
            ordinal: 0,
            object_id: ctx.assignment.preparation.source_mapping[0].object_id,
          }],
        };
        output = { request, resolved };
        answer = { version: 1, outcome: "registered", ...output };
      } else {
        result = JSON.parse(String(args.p_outcome));
        answer = {
          version: 1,
          outcome: "outcome_ready",
          result,
          digest: await executionDigest("outcome", String(args.p_outcome)),
        };
      }
      if (failAfter === op) {
        failAfter = null;
        throw new Error("synthetic lost reply");
      }
      return structuredClone(answer);
    },
    readSource() {
      counts.reads++;
      return Promise.resolve(bytes);
    },
    inspectSource(_i, copy) {
      copy[0] = 255;
      if (mutate) bytes.fill(255);
      return Promise.resolve({
        image: { width: 1, height: 1, format: "png" },
        wav: null,
        mp4: null,
      });
    },
    runtime(value) {
      counts.runtime++;
      const copied = value.read(0);
      value.read(0).fill(255);
      return Promise.resolve([copied]);
    },
    verifyExistingIdentityOutput() {
      counts.retains++;
      return Promise.resolve(new Uint8Array(originalBytes));
    },
    createFreshOutputAndReadBack(_i, _id, value) {
      counts.retains++;
      return Promise.resolve(value);
    },
  };
  return {
    input,
    ctx,
    deps,
    counts,
    calls,
    bytes,
    setLoss(op: PreparationOperation) {
      failAfter = op;
    },
    setTerminal() {
      terminal = true;
    },
    mutateSource() {
      mutate = true;
    },
    saved() {
      return { source, grant, output, result };
    },
  };
}
Deno.test("synthetic preparation journey preserves verified bytes and completes original receipts", async () => {
  const f = await fixture();
  f.mutateSource();
  const result = await runInitialPreparation(
    f.deps,
    f.input,
    new AbortController().signal,
  );
  assertEquals(result.kind, "outcome_ready");
  assertEquals(f.counts.runtime, 1);
  assertEquals(f.counts.issues, 1);
  if (result.kind === "outcome_ready") {
    await validatePreparationOutcome(f.ctx, result.outcome);
  }
  const replay = await runInitialPreparation(
    f.deps,
    f.input,
    new AbortController().signal,
  );
  assertEquals(replay.kind, "outcome_ready");
  assertEquals(f.counts.runtime, 1);
});
Deno.test("lost issuance reply never grants a second transform on retry", async () => {
  const f = await fixture();
  f.setLoss("issue_initial_preparation_execution");
  assertEquals(
    (await runInitialPreparation(f.deps, f.input, new AbortController().signal))
      .kind,
    "recovery_needed",
  );
  assertEquals(
    (await runInitialPreparation(f.deps, f.input, new AbortController().signal))
      .kind,
    "recovery_needed",
  );
  assertEquals(f.counts.runtime, 0);
  assertEquals(f.counts.issues, 1);
});
for (
  const operation of [
    "register_initial_preparation_output",
    "settle_initial_preparation_outcome",
  ] as const
) {
  Deno.test(`lost ${operation} reconciles exact original proof without runtime`, async () => {
    const f = await fixture();
    f.setLoss(operation);
    const first = await runInitialPreparation(
      f.deps,
      f.input,
      new AbortController().signal,
    );
    assert(first.kind === "recovery_needed" && first.known);
    const result = await reconcileInitialPreparationOutput(
      f.deps,
      first.known,
      new AbortController().signal,
    );
    assertEquals(result.kind, "outcome_ready");
    assertEquals(f.counts.runtime, 1);
    assertEquals(f.counts.issues, 1);
  });
}
for (
  const operation of [
    "register_initial_preparation_output",
    "settle_initial_preparation_outcome",
  ] as const
) {
  Deno.test(`local cancellation after known ${operation} does not erase proof`, async () => {
    const f = await fixture(),
      controller = new AbortController(),
      call = f.deps.call;
    f.deps.call = async (op, args, signal) => {
      const v = await call(op, args, signal);
      if (op === operation) controller.abort();
      return v;
    };
    const first = await runInitialPreparation(
      f.deps,
      f.input,
      controller.signal,
    );
    if (operation === "settle_initial_preparation_outcome") {
      assertEquals(first.kind, "outcome_ready");
    } else {
      assert(first.kind === "recovery_needed" && first.known);
      assertEquals(
        (await reconcileInitialPreparationOutput(
          f.deps,
          first.known,
          new AbortController().signal,
        )).kind,
        "outcome_ready",
      );
    }
    assertEquals(f.counts.runtime, 1);
  });
}
Deno.test("cancellation with on-time known runtime output retains only settlement capability", async () => {
  const f = await fixture(),
    controller = new AbortController(),
    runtime = f.deps.runtime;
  f.deps.runtime = async (input, signal) => {
    const result = await runtime(input, signal);
    controller.abort();
    return result;
  };
  const first = await runInitialPreparation(f.deps, f.input, controller.signal);
  assert(first.kind === "recovery_needed" && first.known);
  assertEquals(f.counts.retains, 0);
  assertEquals(
    (await reconcileInitialPreparationOutput(
      f.deps,
      first.known,
      new AbortController().signal,
    )).kind,
    "outcome_ready",
  );
  assertEquals(f.counts.runtime, 1);
});
Deno.test("durable terminal winner prevents known-output reconciliation I/O", async () => {
  const f = await fixture();
  f.setLoss("register_initial_preparation_output");
  const first = await runInitialPreparation(
    f.deps,
    f.input,
    new AbortController().signal,
  );
  assert(first.kind === "recovery_needed" && first.known);
  f.setTerminal();
  assertEquals(
    (await reconcileInitialPreparationOutput(
      f.deps,
      first.known,
      new AbortController().signal,
    )).kind,
    "held",
  );
  assertEquals(f.counts.retains, 0);
  assertEquals(f.counts.runtime, 1);
});
Deno.test("changed source and shared memory never reach sole issue", async () => {
  for (const shared of [false, true]) {
    const f = await fixture();
    if (shared) {
      f.deps.readSource = () =>
        Promise.resolve(new Uint8Array(new SharedArrayBuffer(68)));
    } else f.bytes.fill(255);
    assertEquals(
      (await runInitialPreparation(
        f.deps,
        f.input,
        new AbortController().signal,
      )).kind,
      "recovery_needed",
    );
    assertEquals(f.counts.runtime, 0);
    assertEquals(f.counts.issues, 0);
  }
});
Deno.test("cancelled grant reply consumes issuance but not runtime", async () => {
  const f = await fixture(),
    controller = new AbortController(),
    call = f.deps.call;
  f.deps.call = async (op, args, signal) => {
    const v = await call(op, args, signal);
    if (op === "issue_initial_preparation_execution") controller.abort();
    return v;
  };
  assertEquals(
    (await runInitialPreparation(f.deps, f.input, controller.signal)).kind,
    "recovery_needed",
  );
  assertEquals(f.counts.runtime, 0);
  assertEquals(f.counts.issues, 1);
});
Deno.test("closed receipts reject changed identity, extra facts, partial output and wrong profile", async () => {
  const f = await fixture();
  const result = await runInitialPreparation(
    f.deps,
    f.input,
    new AbortController().signal,
  );
  assert(result.kind === "outcome_ready");
  const source = structuredClone(result.outcome.source_verification);
  source.entries[0].object_id = f.input.owner;
  assertThrows(() => validateSourceReceipt(f.ctx, source));
  const changed = structuredClone(result.outcome);
  changed.output_manifest.entries = [];
  await assertRejects(() => validatePreparationOutcome(f.ctx, changed));
  const changedProfile = structuredClone(result.outcome);
  changedProfile.profile.spec.profile_version++;
  await assertRejects(() => validatePreparationOutcome(f.ctx, changedProfile));
  await assertRejects(() =>
    validatePreparationOutcome(f.ctx, { ...result.outcome, extra: true })
  );
});

/** Advance the monotonic clock without giving timers a macrotask turn. */
async function withClock(
  run: (advance: (ms: number) => void) => Promise<void>,
) {
  const original = Object.getOwnPropertyDescriptor(performance, "now");
  const now = performance.now.bind(performance);
  let offset = 0;
  Object.defineProperty(performance, "now", {
    configurable: true,
    value: () => now() + offset,
  });
  try {
    await run((ms) => {
      offset += ms;
    });
  } finally {
    if (original) Object.defineProperty(performance, "now", original);
    else Reflect.deleteProperty(performance, "now");
  }
}
for (
  const boundary of [
    "source",
    "inspect",
    "runtime",
    "registration",
    "retention",
    "settlement",
  ] as const
) {
  Deno.test(`absolute ${boundary} deadline survives timer starvation`, async () => {
    await withClock(async (advance) => {
      const f = await fixture();
      if (boundary === "source") {
        const read = f.deps.readSource;
        f.deps.readSource = async (...args) => {
          const value = await read(...args);
          advance(30001);
          return value;
        };
      } else if (boundary === "inspect") {
        const inspect = f.deps.inspectSource;
        f.deps.inspectSource = async (...args) => {
          const value = await inspect(...args);
          advance(30001);
          return value;
        };
      } else if (boundary === "runtime") {
        const runtime = f.deps.runtime;
        f.deps.runtime = async (...args) => {
          const value = await runtime(...args);
          advance(201);
          return value;
        };
      } else if (boundary === "retention") {
        const verify = f.deps.verifyExistingIdentityOutput;
        f.deps.verifyExistingIdentityOutput = async (...args) => {
          const value = await verify(...args);
          advance(30001);
          return value;
        };
      } else {
        const call = f.deps.call;
        f.deps.call = async (...args) => {
          const value = await call(...args);
          if (
            args[0] ===
              (boundary === "registration"
                ? "register_initial_preparation_output"
                : "settle_initial_preparation_outcome")
          ) advance(5001);
          return value;
        };
      }
      const result = await runInitialPreparation(
        f.deps,
        f.input,
        new AbortController().signal,
      );
      assertEquals(result.kind, "recovery_needed");
      if (boundary === "source" || boundary === "inspect") {
        assertEquals(f.counts.issues, 0);
      }
      if (boundary === "registration" || boundary === "runtime") {
        assertEquals(f.counts.retains, 0);
      }
      if (boundary === "retention") assertEquals(f.saved().result, null);
      if (boundary === "settlement") {
        // A lost/late acknowledgement recovers the committed exact outcome.
        assert(result.kind === "recovery_needed" && result.known);
        assertEquals(
          (await reconcileInitialPreparationOutput(
            f.deps,
            result.known,
            new AbortController().signal,
          )).kind,
          "outcome_ready",
        );
        assertEquals(f.counts.runtime, 1);
      }
    });
  });
}
Deno.test("identity output has no fresh object write capability", async () => {
  const f = await fixture();
  f.deps.createFreshOutputAndReadBack = () => {
    throw new Error("original source overwrite attempted");
  };
  assertEquals(
    (await runInitialPreparation(f.deps, f.input, new AbortController().signal))
      .kind,
    "outcome_ready",
  );
});

Deno.test("heterogeneous grant budget sums actual frozen roles and rejects aggregate substitution", async () => {
  const ctx = await preparationContext(
    "00000000-0000-4000-8000-000000001002",
    vectors.valid[3].candidate,
    vectors.valid[3].assignment,
    vectors.valid[3].profile,
  );
  const wall = ctx.assignment.preparation.source_mapping.reduce(
    (total, m) =>
      total +
      ctx.profile.spec.rules.find((r) => r.role === m.role)!.limits.wall_ms,
    0,
  );
  assertEquals(preparationWallMs(ctx), wall);
  assert(wall < ctx.profile.spec.limits.wall_ms);
  const grant = {
    version: 1,
    scan_id: ctx.scan_id,
    assignment_digest: ctx.assignment_digest,
    grant_id: "00000000-0000-4000-8000-000000000001",
    source_digest: "a".repeat(64),
    profile_digest: ctx.assignment.preparation.profile_digest,
    artifact_digest: ctx.profile.spec.artifact.sha256,
    issued_at_ms: 100,
    execution_deadline_ms: 5100 + wall,
    registration_deadline_ms: 10100 + wall,
    outcome_deadline_ms: 45100 + wall,
  };
  validateGrant(ctx, grant.source_digest, grant);
  assertThrows(() =>
    validateGrant(ctx, grant.source_digest, {
      ...grant,
      execution_deadline_ms: 5100 + ctx.profile.spec.limits.wall_ms,
    })
  );
});
Deno.test("status schema denies leaked grants and impossible phase combinations", async () => {
  const f = await fixture();
  const status = await f.deps.call(
    "get_initial_preparation_execution_status",
    {},
    new AbortController().signal,
  ) as Record<string, unknown>;
  validatePreparationReply(status);
  assertThrows(() => validatePreparationReply({ ...status, grant: null }));
  assertThrows(() => validatePreparationReply({ ...status, phase: "issued" }));
  assertThrows(() => validatePreparationReply({ ...status, unknown: true }));
});

Deno.test("fresh path fits near-cap grant delivery runtime and registration without a status detour", async () => {
  await withClock(async (advance) => {
    const f = await fixture(), call = f.deps.call, runtime = f.deps.runtime;
    f.deps.call = async (...args) => {
      const value = await call(...args);
      if (
        args[0] === "issue_initial_preparation_execution" ||
        args[0] === "register_initial_preparation_output"
      ) advance(4900);
      return value;
    };
    f.deps.runtime = async (...args) => {
      const value = await runtime(...args);
      advance(190);
      return value;
    };
    assertEquals(
      (await runInitialPreparation(
        f.deps,
        f.input,
        new AbortController().signal,
      )).kind,
      "outcome_ready",
    );
    assertEquals(
      f.calls.filter((op) => op === "get_initial_preparation_execution_status")
        .length,
      1,
    );
    assertEquals(f.counts.runtime, 1);
    assertEquals(f.counts.issues, 1);
  });
});
Deno.test("full measured grant RPC round trip reduces runtime authority", async () => {
  await withClock(async (advance) => {
    const f = await fixture(), call = f.deps.call;
    f.deps.call = async (...args) => {
      const value = await call(...args);
      if (args[0] === "issue_initial_preparation_execution") {
        advance(200);
        (value as Record<string, number>).server_now_ms += 200;
        advance(4700);
      }
      return value;
    };
    // The server samples time 200ms after issuance and delivery takes another
    // 4700ms. Subtracting only return transit would appear to leave 300ms;
    // full measured RTT leaves <=100ms, below the frozen 200ms runtime cap.
    const result = await runInitialPreparation(
      f.deps,
      f.input,
      new AbortController().signal,
    );
    assertEquals(result.kind, "recovery_needed");
    assertEquals(f.counts.runtime, 0);
    assertEquals(f.counts.issues, 1);
    await runInitialPreparation(f.deps, f.input, new AbortController().signal);
    assertEquals(f.counts.runtime, 0);
    assertEquals(f.counts.issues, 1);
  });
});

Deno.test("terminal winner after runtime prevents fresh registration from retaining output", async () => {
  const f = await fixture();
  const runtime = f.deps.runtime;
  f.deps.runtime = async (input, signal) => {
    const result = await runtime(input, signal);
    f.setTerminal();
    return result;
  };
  const result = await runInitialPreparation(
    f.deps,
    f.input,
    new AbortController().signal,
  );
  assertEquals(result.kind, "held");
  assertEquals(f.counts.runtime, 1);
  assertEquals(f.counts.retains, 0);
  assertEquals(
    f.calls.filter((op) => op === "register_initial_preparation_output").length,
    1,
  );
  assertEquals(
    f.calls.filter((op) => op === "settle_initial_preparation_outcome").length,
    0,
  );
});
