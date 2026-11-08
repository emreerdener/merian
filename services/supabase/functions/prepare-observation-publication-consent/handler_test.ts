import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HistoryError } from "../_shared/analysisHistory/contract.ts";
import { parsePublicationConsentRequest } from "../_shared/analysisHistory/publicationConsent.ts";
import { prepareObservationPublicationConsent } from "./handler.ts";
import { publicationConsentRepository } from "./db.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const input = () => ({
  schema_version: 1,
  observation_id: id(1),
  analysis_id: id(2),
});
const receipt = () => ({
  ...input(),
  expected_observation_revision: 2,
  expected_review_revision: 0,
  taxonomy_version_id: id(5),
  initial_taxon_id: null,
  media: [{
    media_id: id(6),
    content_type: "image/jpeg",
    byte_count: 10,
    sha256: "a".repeat(64),
  }],
});
const req = () => new Request("https://example.invalid", { method: "POST" });
Deno.test("publication consent returns an immutable exact analysis snapshot without creating an operation", async () => {
  const body = input();
  const response = await prepareObservationPublicationConsent(
    req(),
    body,
    id(4),
    {
      read: (owner, request) => {
        assertEquals(owner, id(4));
        assertEquals(Object.isFrozen(request), true);
        body.analysis_id = id(9);
        assertEquals(request.analysis_id, id(2));
        return Promise.resolve(receipt());
      },
    },
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), receipt());
  assertEquals(response.headers.get("Cache-Control"), "private, no-store");
});
Deno.test("publication consent rejects caller owner, latest lookup, malformed IDs and versions before RPC", async () => {
  for (
    const body of [
      null,
      [],
      {},
      { ...input(), owner_id: id(4) },
      { ...input(), operation_id: id(3) },
      { ...input(), analysis_id: null },
      { ...input(), observation_id: 1 },
      { ...input(), schema_version: 2 },
      { ...input(), analysis_id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA" },
    ]
  ) {
    let calls = 0;
    const response = await prepareObservationPublicationConsent(
      req(),
      body,
      id(4),
      {
        read: () => {
          calls++;
          return Promise.resolve(receipt());
        },
      },
    );
    assertEquals(response.status, 400);
    assertEquals(calls, 0);
    assertEquals(response.headers.get("Cache-Control"), "private, no-store");
    await response.body?.cancel();
  }
});
Deno.test("publication consent fails closed on private extra fields, wrong identities and unknown states", async () => {
  for (
    const patch of [
      { analysis_id: id(8) },
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
    const response = await prepareObservationPublicationConsent(
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
Deno.test("publication consent hides deletion and foreign ownership with one opaque not-found response", async () => {
  for (
    const code of [
      "analysis_history_not_found",
      "analysis_history_deleted",
    ] as const
  ) {
    const response = await prepareObservationPublicationConsent(
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
Deno.test("publication consent preserves known conflicts and sanitizes unknown diagnostics", async () => {
  for (
    const [error, status] of [
      [new HistoryError("analysis_history_revision_conflict"), 409],
      [new HistoryError("analysis_history_operation_conflict"), 409],
      [new Error("sensitive diagnostic"), 503],
    ] as const
  ) {
    const response = await prepareObservationPublicationConsent(
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
Deno.test("publication consent RPC uses only authenticated owner and exact operation with bounded transport", async () => {
  let calls = 0;
  const client = {
    rpc: (name: string, args: unknown) => ({
      abortSignal: (signal: AbortSignal) => {
        calls++;
        assertEquals(name, "prepare_owned_observation_publication_consent");
        assertEquals(args, {
          p_owner: id(4),
          p_observation: id(1),
          p_analysis: id(2),
        });
        assertEquals(signal instanceof AbortSignal, true);
        return Promise.resolve({ data: receipt(), error: null });
      },
    }),
  } as unknown as SupabaseClient;
  assertEquals(
    await publicationConsentRepository(client).read(
      id(4),
      parsePublicationConsentRequest(input()),
    ),
    receipt(),
  );
  assertEquals(calls, 1);
});
Deno.test("publication consent RPC does not retry or leak database and transport failures", async () => {
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
        publicationConsentRepository(client).read(
          id(4),
          parsePublicationConsentRequest(input()),
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
      publicationConsentRepository(client).read(
        id(4),
        parsePublicationConsentRequest(input()),
      ),
    HistoryError,
    "analysis_history_unavailable",
  );
});

Deno.test("consent candidate contract preserves manifest order and all 64 candidates", async () => {
  const data = receipt();
  data.media = Array.from(
    { length: 64 },
    (_, n) => ({ ...data.media[0], media_id: id(100 - n) }),
  );
  const response = await prepareObservationPublicationConsent(
    req(),
    input(),
    id(4),
    { read: () => Promise.resolve(data) },
  );
  assertEquals(response.status, 200);
  assertEquals((await response.json()).media, data.media);
});
Deno.test("consent snapshots reject invalid bounds, duplicates, private keys, nonnull taxon and malformed metadata", async () => {
  const photo = receipt().media[0];
  for (
    const patch of [
      { expected_observation_revision: -1 },
      { expected_review_revision: 1.5 },
      { expected_review_revision: 2147483647 },
      { taxonomy_version_id: null },
      { initial_taxon_id: id(8) },
      { media: [] },
      {
        media: Array.from(
          { length: 65 },
          (_, n) => ({ ...photo, media_id: id(100 + n) }),
        ),
      },
      { media: [photo, photo] },
      { media: [{ ...photo, object_id: id(9) }] },
      { media: [{ ...photo, content_type: "image/gif" }] },
      { media: [{ ...photo, byte_count: 0 }] },
      { media: [{ ...photo, sha256: "A".repeat(64) }] },
      {
        media: [{ ...photo, byte_count: 33554432 }, {
          ...photo,
          media_id: id(7),
        }],
      },
    ]
  ) {
    const response = await prepareObservationPublicationConsent(
      req(),
      input(),
      id(4),
      { read: () => Promise.resolve({ ...receipt(), ...patch }) },
    );
    assertEquals(response.status, 503);
    assertEquals((await response.json()).code, "analysis_history_unavailable");
  }
});
