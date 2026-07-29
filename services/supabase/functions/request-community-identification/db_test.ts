import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type AtomicCommunityIdentificationPayload,
  fetchInitialTaxonNodeId,
  invokeAtomicCommunityIdentificationRequest,
} from "./db.ts";

const payload: AtomicCommunityIdentificationPayload = {
  p_scan_id: "00000000-0000-4000-8000-000000000001",
  p_user_id: "00000000-0000-4000-8000-000000000002",
  p_note: null,
  p_location_sharing: null,
  p_species_common_name: null,
  p_media_rows: [{
    kind: "image",
    url: "https://media.merian.app/test.webp",
    thumbnail_url: "https://media.merian.app/test.webp",
    order_index: 0,
    duration_seconds: null,
    has_audio: false,
  }],
  p_initial_taxon_node_id: "00000000-0000-4000-8000-000000000003",
  p_taxonomy_version_id: "00000000-0000-4000-8000-000000000004",
};

function mockClient(
  results: Array<{
    data: unknown;
    error: { code: string; message: string } | null;
  }>,
): { client: SupabaseClient; calls: () => number } {
  let callCount = 0;
  const client = {
    rpc(
      name: string,
      receivedPayload: AtomicCommunityIdentificationPayload,
    ) {
      assertEquals(name, "request_community_identification_atomically");
      assertEquals(receivedPayload, payload);
      const result = results[Math.min(callCount, results.length - 1)];
      callCount += 1;
      return Promise.resolve(result);
    },
  } as unknown as SupabaseClient;
  return { client, calls: () => callCount };
}

Deno.test("atomic Community request retries one concurrent needs-ID race", async () => {
  const expected = {
    id: "00000000-0000-4000-8000-000000000005",
  };
  const { client, calls } = mockClient([
    {
      data: null,
      error: {
        code: "P0001",
        message:
          "Wait for the community to identify this request before sharing it to Explore.",
      },
    },
    { data: expected, error: null },
  ]);

  const result = await invokeAtomicCommunityIdentificationRequest(
    payload,
    client,
  );

  assertEquals(calls(), 2);
  assertEquals(result.data, expected);
  assertEquals(result.error, null);
});

Deno.test("atomic Community request does not retry unrelated database errors", async () => {
  const expected = {
    data: null,
    error: { code: "22023", message: "Invalid media" },
  };
  const { client, calls } = mockClient([expected]);

  const result = await invokeAtomicCommunityIdentificationRequest(
    payload,
    client,
  );

  assertEquals(calls(), 1);
  assertEquals(result.data, null);
  assertEquals(result.error?.code, expected.error.code);
  assertEquals(result.error?.message, expected.error.message);
});

Deno.test("Community request fails closed when taxonomy synchronization fails", async () => {
  let rpcCalls = 0;
  const client = {
    rpc(name: string) {
      assertEquals(name, "sync_taxon_nodes_from_species_dictionary");
      rpcCalls += 1;
      return Promise.resolve({
        data: null,
        error: { message: "taxonomy unavailable" },
      });
    },
  } as unknown as SupabaseClient;

  await assertRejects(
    () =>
      fetchInitialTaxonNodeId(
        "00000000-0000-4000-8000-000000000006",
        client,
      ),
    Error,
    "Failed to synchronize taxonomy nodes: taxonomy unavailable",
  );
  assertEquals(rpcCalls, 1);
});
