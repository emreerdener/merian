import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import { parsePublicationOperationRequest } from "../_shared/analysisHistory/publicationOperation.ts";
import { requestObservationPublication } from "./handler.ts";
import { publicationOperationRepository } from "./db.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = () => ({
  schema_version: 1,
  operation_id: id(1),
  observation_id: id(2),
  analysis_id: id(3),
  expected_observation_revision: 4,
  expected_review_revision: 2,
  taxonomy_version_id: id(4),
  initial_taxon_id: null,
  note: "Synthetic note",
  media_ids: [id(6), id(5)],
});
const receipt = () => ({
  schema_version: 1,
  operation_id: id(1),
  observation_id: id(2),
  analysis_id: id(3),
  status: "accepted",
  admitted_at: "2026-10-04T00:00:00Z",
});
const req = () => new Request("https://example.invalid", { method: "POST" });
Deno.test("publication intake freezes exact ordered consent and returns only durable acceptance", async () => {
  const body = input();
  const result = await requestObservationPublication(req(), body, id(7), {
    admit: (owner, request) => {
      assertEquals(owner, id(7));
      assertEquals(request.media_ids, [id(6), id(5)]);
      body.media_ids.reverse();
      body.operation_id = id(9);
      body.note = "changed";
      assertEquals(request.operation_id, id(1));
      assertEquals(request.note, "Synthetic note");
      assertEquals(request.media_ids, [id(6), id(5)]);
      return Promise.resolve(receipt());
    },
  });
  assertEquals(result.status, 202);
  assertEquals(result.headers.get("Cache-Control"), "private, no-store");
  assertEquals(await result.json(), receipt());
});
Deno.test("publication intake rejects extra identities, URLs, repeated media and invalid bounds before admission", async () => {
  for (
    const patch of [
      { owner_id: id(9) },
      { url: "https://example.invalid" },
      { media_ids: [id(5), id(5)] },
      { media_ids: [] },
      { expected_review_revision: true },
      { note: "x".repeat(1001) },
      { operation_id: 4 },
      { note: "😀".repeat(1000) },
    ]
  ) {
    let called = false;
    const result = await requestObservationPublication(
      req(),
      { ...input(), ...patch },
      id(7),
      {
        admit: () => {
          called = true;
          return Promise.resolve(receipt());
        },
      },
    );
    assertEquals(result.status, 400);
    assertEquals(called, false);
  }
  assertThrows(() =>
    parsePublicationOperationRequest({
      ...input(),
      media_ids: [id(5), id(6), id(7), id(8), id(9), id(10), id(11)],
    })
  );
});
Deno.test("publication intake rejects wrong receipt identity and private extra fields as server failures", async () => {
  for (
    const patch of [
      { operation_id: id(8) },
      { observation_id: id(8) },
      { analysis_id: id(8) },
      { source: {} },
      { status: "published" },
      { admitted_at: "invalid" },
    ]
  ) {
    const result = await requestObservationPublication(req(), input(), id(7), {
      admit: () => Promise.resolve({ ...receipt(), ...patch }),
    });
    assertEquals(result.status, 503);
    assertEquals(
      (await result.json()).code,
      "analysis_history_unavailable",
    );
  }
});
Deno.test("publication intake maps safe conflicts and hides arbitrary provider or database diagnostics", async () => {
  for (
    const [error, status] of [
      [new HistoryError("analysis_history_revision_conflict"), 409],
      [new HistoryError("analysis_history_not_found"), 404],
      [new Error("private diagnostic"), 503],
    ] as const
  ) {
    const result = await requestObservationPublication(req(), input(), id(7), {
      admit: () => Promise.reject(error),
    });
    assertEquals(result.status, status);
    assertEquals((await result.text()).includes("private diagnostic"), false);
  }
});
Deno.test("publication intake RPC scopes owner, exact request and original hash with a deadline", async () => {
  const request = parsePublicationOperationRequest(input());
  let calls = 0;
  const client = {
    rpc: (name: string, args: unknown) => ({
      abortSignal: (signal: AbortSignal) => {
        calls++;
        assertEquals(name, "admit_owned_observation_publication");
        assertEquals(args, {
          p_owner: id(7),
          p_request: request,
          p_ip_hash: "a".repeat(64),
        });
        assertEquals(signal instanceof AbortSignal, true);
        return Promise.resolve({ data: receipt(), error: null });
      },
    }),
  } as unknown as SupabaseClient;
  assertEquals(
    await publicationOperationRepository(client).admit(
      id(7),
      request,
      "a".repeat(64),
    ),
    receipt(),
  );
  assertEquals(calls, 1);
});
Deno.test("publication intake RPC failure is sanitized and never automatically retried", async () => {
  let calls = 0;
  const client = {
    rpc: () => ({
      abortSignal: () => {
        calls++;
        return Promise.resolve({
          data: null,
          error: { message: "private diagnostic" },
        });
      },
    }),
  } as unknown as SupabaseClient;
  await assertRejects(
    () =>
      publicationOperationRepository(client).admit(
        id(7),
        parsePublicationOperationRequest(input()),
        "a".repeat(64),
      ),
    HistoryError,
    "analysis_history_unavailable",
  );
  assertEquals(calls, 1);
});
