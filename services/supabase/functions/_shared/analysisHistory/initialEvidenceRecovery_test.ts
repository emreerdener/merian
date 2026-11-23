import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import page from "./fixtures/page-v8.json" with { type: "json" };
import { HistoryError } from "./contract.ts";
import { initialRetentionRequest } from "./initialEvidenceRetention.ts";
import {
  parseAcceptedInitialResult,
  recoverAcceptedInitialResult,
} from "./initialEvidenceRecovery.ts";

async function fixture() {
  const snapshot = JSON.parse(page.items[0].snapshot);
  const request = await initialRetentionRequest({
    schema_version: 1,
    scan_id: snapshot.observation_id,
    generation: snapshot.initial_evidence.generation,
    evidence_digest: snapshot.request_digest,
    evidence_manifest: snapshot.evidence_manifest,
  });
  const accepted = {
    schema_version: 1,
    owner_id: page.owner_id,
    scan_id: request.scan_id,
    generation: request.generation,
    evidence_digest: request.evidence_digest,
    result: snapshot.result,
    species_id: null,
    result_digest: "a".repeat(64),
  };
  return { request, accepted };
}

Deno.test("accepted initial recovery owns exact result and fences all identities", async () => {
  const { request, accepted } = await fixture();
  const recovered = parseAcceptedInitialResult(
    accepted,
    page.owner_id,
    request,
  )!;
  const original = structuredClone(accepted.result);
  accepted.result.ai_reasoning = "Changed caller value";
  assertEquals(recovered.result, original);
  assertEquals(parseAcceptedInitialResult(null, page.owner_id, request), null);
  for (
    const key of [
      "owner_id",
      "scan_id",
      "generation",
      "evidence_digest",
      "result_digest",
    ]
  ) {
    assertThrows(() =>
      parseAcceptedInitialResult(
        { ...accepted, [key]: "invalid" },
        page.owner_id,
        request,
      )
    );
  }
  assertThrows(() =>
    parseAcceptedInitialResult(
      { ...accepted, unexpected: true },
      page.owner_id,
      request,
    )
  );
  assertThrows(() =>
    parseAcceptedInitialResult(
      { ...accepted, result: { ...original, scan_id: crypto.randomUUID() } },
      page.owner_id,
      request,
    )
  );
  assertThrows(() =>
    parseAcceptedInitialResult(undefined, page.owner_id, request)
  );
});

Deno.test("accepted recovery distinguishes a verified null from RPC failure", async () => {
  const { request, accepted } = await fixture();
  for (const data of [null, accepted]) {
    const client = {
      rpc(name: string, args: unknown) {
        assertEquals(name, "recover_owned_initial_result");
        assertEquals(args, { p_owner: page.owner_id, p_request: request });
        return { abortSignal: () => Promise.resolve({ data, error: null }) };
      },
    } as unknown as SupabaseClient;
    const result = await recoverAcceptedInitialResult(
      client,
      page.owner_id,
      request,
      new AbortController().signal,
    );
    assertEquals(
      result,
      parseAcceptedInitialResult(data, page.owner_id, request),
    );
  }
  for (
    const message of ["analysis_history_operation_conflict", "private detail"]
  ) {
    const client = {
      rpc: () => ({
        abortSignal: () => Promise.resolve({ data: null, error: { message } }),
      }),
    } as unknown as SupabaseClient;
    await assertRejects(
      () =>
        recoverAcceptedInitialResult(
          client,
          page.owner_id,
          request,
          new AbortController().signal,
        ),
      HistoryError,
      message === "analysis_history_operation_conflict"
        ? message
        : "analysis_history_unavailable",
    );
  }
});

Deno.test("accepted recovery terminates when a transport ignores cancellation", async () => {
  const { request } = await fixture(), controller = new AbortController();
  let entered!: () => void;
  const started = new Promise<void>((resolve) => {
    entered = resolve;
  });
  const client = {
    rpc: () => ({
      abortSignal: () => {
        entered();
        return new Promise(() => {});
      },
    }),
  } as unknown as SupabaseClient;
  const recovery = recoverAcceptedInitialResult(
    client,
    page.owner_id,
    request,
    controller.signal,
  );
  await started;
  controller.abort();
  await assertRejects(
    () => recovery,
    HistoryError,
    "analysis_history_unavailable",
  );
});
