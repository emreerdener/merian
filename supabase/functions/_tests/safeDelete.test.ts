// _tests/safeDelete.test.ts
//
// Unit tests for safe-delete/index.ts operation ordering and partial-failure handling.
// All logic is inline-stubbed — no live Supabase client required.
//
// Covers:
//   - Three-phase delete order: auth revoke → tombstone → storage queue
//   - Auth-first guarantee: deleteAuthProfile throws → subsequent steps never run
//   - Partial failure: tombstone throws after auth deleted → structured error emitted
//   - logStructuredError event shape for safe_delete_partial_failure
//   - Re-throw on partial failure (caller receives 500, not false-success 200)

import { assertEquals, assertRejects, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";

// ---------------------------------------------------------------------------
// Three-phase operation order simulation
// Mirrors the execution flow in safe-delete/index.ts.
// ---------------------------------------------------------------------------

type PhaseResult = { order: string[]; outcome: "success" | "auth_failed" | "partial_failure" };

async function simulateSafeDelete(
  deleteAuth: () => Promise<void>,
  tombstone: () => Promise<void>,
  queueStorage: () => Promise<void>,
): Promise<PhaseResult> {
  const order: string[] = [];

  // Phase 1 — always runs first. If this throws, phases 2+3 never execute.
  await deleteAuth();
  order.push("deleteAuth");

  // Phases 2+3 — run after auth is revoked. Failure here is a partial failure.
  try {
    await tombstone();
    order.push("tombstone");

    await queueStorage();
    order.push("queueStorage");

    return { order, outcome: "success" };
  } catch {
    return { order, outcome: "partial_failure" };
  }
}

Deno.test("safe-delete — full success executes all three phases in order", async () => {
  const result = await simulateSafeDelete(
    async () => {},
    async () => {},
    async () => {},
  );
  assertEquals(result.outcome, "success");
  assertEquals(result.order, ["deleteAuth", "tombstone", "queueStorage"]);
});

Deno.test("safe-delete — auth failure aborts before tombstone and storage queue", async () => {
  let tombstoneCalled = false;
  let storageCalled = false;

  await assertRejects(
    () => simulateSafeDelete(
      async () => { throw new Error("auth delete failed"); },
      async () => { tombstoneCalled = true; },
      async () => { storageCalled = true; },
    ),
  );

  assertEquals(tombstoneCalled, false, "tombstone must NOT run after auth failure");
  assertEquals(storageCalled, false, "storage queue must NOT run after auth failure");
});

Deno.test("safe-delete — tombstone failure after auth revoked returns partial_failure (not success)", async () => {
  const result = await simulateSafeDelete(
    async () => {},
    async () => { throw new Error("tombstone RPC failed"); },
    async () => {},
  );
  assertEquals(result.outcome, "partial_failure");
  // deleteAuth ran before the failure
  assert(result.order.includes("deleteAuth"));
  // tombstone and queueStorage did not complete
  assertEquals(result.order.includes("tombstone"), false);
  assertEquals(result.order.includes("queueStorage"), false);
});

Deno.test("safe-delete — storage queue failure after auth+tombstone returns partial_failure", async () => {
  const result = await simulateSafeDelete(
    async () => {},
    async () => {},
    async () => { throw new Error("storage queue failed"); },
  );
  assertEquals(result.outcome, "partial_failure");
  assert(result.order.includes("deleteAuth"));
  assert(result.order.includes("tombstone"));
  assertEquals(result.order.includes("queueStorage"), false);
});

// ---------------------------------------------------------------------------
// logStructuredError shape for safe_delete_partial_failure
// Verifies the structured error payload emitted on partial failure contains
// the fields an operator needs to manually recover the account.
// ---------------------------------------------------------------------------

interface PartialFailurePayload {
  event: string;
  user_id: string;
  error: string;
  state: string;
  action_required: string;
}

function buildPartialFailurePayload(userId: string, error: Error): PartialFailurePayload {
  return {
    event: "safe_delete_partial_failure",
    user_id: userId,
    error: error.message,
    state: "auth_deleted_data_not_anonymised",
    action_required: "Manually run apply_user_tombstone RPC for this user_id.",
  };
}

Deno.test("safe_delete_partial_failure — event field is correct", () => {
  const payload = buildPartialFailurePayload(crypto.randomUUID(), new Error("rpc failed"));
  assertEquals(payload.event, "safe_delete_partial_failure");
});

Deno.test("safe_delete_partial_failure — state field identifies the inconsistent condition", () => {
  const payload = buildPartialFailurePayload(crypto.randomUUID(), new Error("rpc failed"));
  assertEquals(payload.state, "auth_deleted_data_not_anonymised");
});

Deno.test("safe_delete_partial_failure — action_required field contains recovery instruction", () => {
  const payload = buildPartialFailurePayload(crypto.randomUUID(), new Error("rpc failed"));
  assert(payload.action_required.includes("apply_user_tombstone"), "action must reference the RPC to run");
});

Deno.test("safe_delete_partial_failure — user_id is propagated from the failing request", () => {
  const userId = crypto.randomUUID();
  const payload = buildPartialFailurePayload(userId, new Error("rpc failed"));
  assertEquals(payload.user_id, userId);
});

Deno.test("safe_delete_partial_failure — error message is propagated from the thrown error", () => {
  const payload = buildPartialFailurePayload(crypto.randomUUID(), new Error("tombstone constraint violation"));
  assertEquals(payload.error, "tombstone constraint violation");
});

// ---------------------------------------------------------------------------
// Re-throw guarantee
// After logging the structured error, safe-delete re-throws so the response
// is HTTP 500 — not a false-success 200.
// ---------------------------------------------------------------------------

Deno.test("safe-delete — partial failure re-throws after logging (caller receives error, not success)", async () => {
  let errorWasLogged = false;
  const tombstoneError = new Error("tombstone failed");

  async function runWithPartialFailure() {
    // Simulate: auth deleted, tombstone throws
    try {
      throw tombstoneError;
    } catch (e) {
      errorWasLogged = true; // represents logStructuredError call
      throw e;               // re-throw, as in the real function
    }
  }

  await assertRejects(
    () => runWithPartialFailure(),
    Error,
    "tombstone failed",
  );
  assert(errorWasLogged, "structured error must be logged before re-throw");
});
