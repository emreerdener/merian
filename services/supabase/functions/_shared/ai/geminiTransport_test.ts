import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  decodeGeminiApplication,
  enterGeminiTransport,
  geminiReservationTransport,
} from "./geminiTransport.ts";
import { assertGeminiLegacyDispatchOpen } from "./geminiProfiles.ts";
const id = "00000000-0000-4000-8000-000000000001";
function client(
  handler: (name: string, args: Record<string, unknown>) => unknown,
) {
  return {
    rpc(name: string, args: Record<string, unknown>) {
      return {
        retry() {
          return this;
        },
        abortSignal() {
          return Promise.resolve(handler(name, args));
        },
      };
    },
  } as unknown as SupabaseClient;
}
Deno.test("worker pauses after its admission permit, suspension fences transport and records live non-invocation", async () => {
  let suspended = false, calls = 0, proofs = 0;
  const db = client((name) => {
    if (name === "authorize_gemini_transport") {
      return suspended
        ? { data: null, error: { message: "gemini_dispatch_closed" } }
        : { data: id, error: null };
    }
    if (name === "record_gemini_non_invocation") {
      proofs++;
      return { data: true, error: null };
    }
    throw new Error("unexpected RPC");
  });
  const hooks = geminiReservationTransport(db, id, {
    id,
    leaseToken: id,
    attemptCount: 1,
  });
  // Existing product admission/dispatch permit is not a transport witness.
  const initialPermit = true;
  await Promise.resolve();
  suspended = true;
  assertEquals(initialPermit, true);
  await assertRejects(async () => {
    await enterGeminiTransport(hooks, "gemini-3.8-flash");
    calls++;
  });
  assertEquals(calls, 0);
  assertEquals(proofs, 1);
});
Deno.test("lost final authorization acknowledgement never becomes a non-invocation proof or second call", async () => {
  let claims = 0, proofs = 0;
  const db = client((name) => {
    if (name === "authorize_gemini_transport") {
      claims++;
      return { data: null, error: { message: "network failure" } };
    }
    if (name === "record_gemini_non_invocation") proofs++;
    throw new Error("unexpected RPC");
  });
  const hooks = geminiReservationTransport(db, id, {
    id,
    leaseToken: id,
    attemptCount: 1,
  });
  await assertRejects(() => enterGeminiTransport(hooks, "gemini-3.8-flash"));
  await assertRejects(() => enterGeminiTransport(hooks, "gemini-3.8-flash"));
  assertEquals(claims, 1);
  assertEquals(proofs, 0);
});
Deno.test("legacy final boundary closes at November 30 and stays closed across provider rerouting", () => {
  for (const model of ["gemini-2.5-flash", "gemini-2.5-pro"]) {
    assertGeminiLegacyDispatchOpen(
      model,
      Date.parse("2026-11-29T23:59:59.999Z"),
    );
    for (const date of ["2026-11-30T00:00:00Z", "2026-12-01T00:00:00Z"]) {
      let failed = false;
      try {
        assertGeminiLegacyDispatchOpen(model, Date.parse(date));
      } catch {
        failed = true;
      }
      assertEquals(failed, true);
    }
  }
  assertGeminiLegacyDispatchOpen(
    "gemini-3.8-flash",
    Date.parse("2026-12-01T00:00:00Z"),
  );
});

Deno.test("provider boundary fails closed without durable execution ownership", async () => {
  await assertRejects(
    () => enterGeminiTransport(undefined, "gemini-3.8-flash"),
    Error,
    "gemini_transport_authority_required",
  );
});

Deno.test("application acceptance is recorded only after strict decoding", async () => {
  const outcomes: string[] = [];
  const hooks = {
    beforeTransport: async () => {},
    recordResponse: async () => {},
    recordApplicationOutcome: (outcome: string) => {
      outcomes.push(outcome);
      return Promise.resolve();
    },
  };
  await assertRejects(() =>
    decodeGeminiApplication(hooks, () => JSON.parse("malformed"))
  );
  assertEquals(outcomes, ["error"]);
  const result = await decodeGeminiApplication(
    hooks,
    () => ({ refusal: true }),
    () => "refusal",
  );
  assertEquals(result, { refusal: true });
  assertEquals(outcomes, ["error", "refusal"]);
});
Deno.test("lost application outcome acknowledgement never rewrites accepted evidence as error", async () => {
  const outcomes: string[] = [];
  await assertRejects(() =>
    decodeGeminiApplication({
      beforeTransport: async () => {},
      recordResponse: async () => {},
      recordApplicationOutcome: (outcome) => {
        outcomes.push(outcome);
        return Promise.reject(new Error("lost acknowledgement"));
      },
    }, () => "accepted")
  );
  assertEquals(outcomes, ["success"]);
});
