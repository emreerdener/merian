import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import { parsePublicationStatusRequest } from "../_shared/analysisHistory/publicationStatus.ts";
import { getObservationPublicationStatus } from "./handler.ts";
import { publicationStatusRepository } from "./db.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = () => ({
  schema_version: 1,
  observation_id: id(1),
  operation_id: id(2),
});
const receipt = (status = "accepted") => ({
  ...input(),
  analysis_id: id(3),
  status,
});
const req = () => new Request("https://example.invalid", { method: "POST" });
Deno.test("publication status exposes only the exact saved operation's five fields for every state", async () => {
  for (
    const status of [
      "accepted",
      "processing",
      "photos_approved",
      "needs_action",
      "admitted",
    ]
  ) {
    const body = input();
    const response = await getObservationPublicationStatus(req(), body, id(4), {
      read: (owner, request) => {
        assertEquals(owner, id(4));
        assertEquals(Object.isFrozen(request), true);
        body.operation_id = id(9);
        assertEquals(request.operation_id, id(2));
        return Promise.resolve(receipt(status));
      },
    });
    assertEquals(response.status, 200);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    assertEquals(await response.json(), receipt(status));
  }
});
Deno.test("publication status rejects caller owner, latest lookup, malformed IDs and versions before RPC", async () => {
  for (
    const body of [
      null,
      [],
      {},
      { ...input(), owner_id: id(4) },
      { ...input(), analysis_id: id(3) },
      { ...input(), operation_id: null },
      { ...input(), observation_id: 1 },
      { ...input(), schema_version: 2 },
      { ...input(), operation_id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA" },
    ]
  ) {
    let calls = 0;
    const response = await getObservationPublicationStatus(req(), body, id(4), {
      read: () => {
        calls++;
        return Promise.resolve(receipt());
      },
    });
    assertEquals(response.status, 400);
    assertEquals(calls, 0);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    await response.body?.cancel();
  }
});
Deno.test("publication status fails closed on private extra fields, wrong identities and unknown states", async () => {
  for (
    const patch of [
      { operation_id: id(8) },
      { observation_id: id(8) },
      { schema_version: 2 },
      { analysis_id: null },
      { status: "published" },
      { reason: "private" },
      { post_id: id(9) },
      { source: {} },
      { note: "private" },
      { work_token: id(5) },
    ]
  ) {
    const response = await getObservationPublicationStatus(
      req(),
      input(),
      id(4),
      {
        read: () => Promise.resolve({ ...receipt(), ...patch }),
      },
    );
    assertEquals(response.status, 503);
    assertEquals((await response.json()).code, "analysis_history_unavailable");
  }
});
Deno.test("publication status hides deletion and foreign ownership with one opaque not-found response", async () => {
  for (
    const code of [
      "analysis_history_not_found",
      "analysis_history_deleted",
    ] as const
  ) {
    const response = await getObservationPublicationStatus(
      req(),
      input(),
      id(4),
      {
        read: () => Promise.reject(new HistoryError(code)),
      },
    );
    assertEquals(response.status, 404);
    assertEquals((await response.json()).code, "analysis_history_not_found");
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
  }
});
Deno.test("publication status preserves known conflicts and sanitizes unknown diagnostics", async () => {
  for (
    const [error, status] of [
      [new HistoryError("analysis_history_revision_conflict"), 409],
      [new HistoryError("analysis_history_operation_conflict"), 409],
      [new Error("sensitive diagnostic"), 503],
    ] as const
  ) {
    const response = await getObservationPublicationStatus(
      req(),
      input(),
      id(4),
      { read: () => Promise.reject(error) },
    );
    assertEquals(response.status, status);
    assertEquals(
      (await response.text()).includes("sensitive diagnostic"),
      false,
    );
  }
});
Deno.test("publication status RPC uses only authenticated owner and exact operation with bounded transport", async () => {
  let calls = 0;
  const client = {
    rpc: (name: string, args: unknown) => ({
      abortSignal: (signal: AbortSignal) => {
        calls++;
        assertEquals(name, "read_owned_observation_publication_status");
        assertEquals(args, {
          p_owner: id(4),
          p_observation: id(1),
          p_operation: id(2),
        });
        assertEquals(signal instanceof AbortSignal, true);
        return Promise.resolve({ data: receipt(), error: null });
      },
    }),
  } as unknown as SupabaseClient;
  assertEquals(
    await publicationStatusRepository(client).read(
      id(4),
      parsePublicationStatusRequest(input()),
    ),
    receipt(),
  );
  assertEquals(calls, 1);
});
Deno.test("publication status RPC does not retry or leak database and transport failures", async () => {
  for (
    const message of [
      "private diagnostic",
      "analysis_history_deleted",
      "analysis_history_not_found",
      "analysis_history_operation_conflict",
    ]
  ) {
    let calls = 0;
    const client = {
      rpc: () => ({
        abortSignal: () => {
          calls++;
          return Promise.resolve({ data: receipt(), error: { message } });
        },
      }),
    } as unknown as SupabaseClient;
    await assertRejects(
      () =>
        publicationStatusRepository(client).read(
          id(4),
          parsePublicationStatusRequest(input()),
        ),
      HistoryError,
      message === "private diagnostic"
        ? "analysis_history_unavailable"
        : message,
    );
    assertEquals(calls, 1);
  }
  const client = {
    rpc: () => {
      throw new Error("private transport diagnostic");
    },
  } as unknown as SupabaseClient;
  await assertRejects(
    () =>
      publicationStatusRepository(client).read(
        id(4),
        parsePublicationStatusRequest(input()),
      ),
    HistoryError,
    "analysis_history_unavailable",
  );
});
