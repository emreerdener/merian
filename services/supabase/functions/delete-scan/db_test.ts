import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  completeScanDeletion,
  fetchScanRecord,
  requestScanDeletion,
} from "./db.ts";

function rpcClient(
  result: { data: unknown; error: { message: string } | null },
  calls: Array<{ name: string; args: Record<string, unknown> }> = [],
): SupabaseClient {
  return {
    rpc(name: string, args: Record<string, unknown>) {
      calls.push({ name, args });
      return Promise.resolve(result);
    },
  } as unknown as SupabaseClient;
}

Deno.test("scan deletion persists an exact owner fence before erasure", async () => {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await requestScanDeletion(
    "00000000-0000-4000-8000-00000000d201",
    "00000000-0000-4000-8000-00000000d202",
    rpcClient({ data: "accepted", error: null }, calls),
  );

  assertEquals(result, "accepted");
  assertEquals(calls, [{
    name: "request_scan_deletion",
    args: {
      p_scan_id: "00000000-0000-4000-8000-00000000d201",
      p_user_id: "00000000-0000-4000-8000-00000000d202",
    },
  }]);
});

Deno.test("scan deletion request fails closed on database and shape errors", async () => {
  await assertRejects(
    () =>
      requestScanDeletion(
        crypto.randomUUID(),
        crypto.randomUUID(),
        rpcClient({ data: null, error: { message: "timeout" } }),
      ),
    Error,
    "Failed to persist scan deletion",
  );
  await assertRejects(
    () =>
      requestScanDeletion(
        crypto.randomUUID(),
        crypto.randomUUID(),
        rpcClient({ data: "unexpected", error: null }),
      ),
    Error,
    "invalid state",
  );
});

Deno.test("scan deletion completion requires the durable owner fence", async () => {
  await completeScanDeletion(
    "00000000-0000-4000-8000-00000000d203",
    "00000000-0000-4000-8000-00000000d204",
    rpcClient({ data: true, error: null }),
  );
  await assertRejects(
    () =>
      completeScanDeletion(
        crypto.randomUUID(),
        crypto.randomUUID(),
        rpcClient({ data: false, error: null }),
      ),
    Error,
    "lost its durable owner fence",
  );
});

function scanLookupClient(
  result: {
    data: unknown;
    error: { message: string } | null;
  },
): SupabaseClient {
  return {
    from() {
      return {
        select() {
          return {
            eq() {
              return {
                maybeSingle: () => Promise.resolve(result),
              };
            },
          };
        },
      };
    },
  } as unknown as SupabaseClient;
}

Deno.test("canonical scan lookup distinguishes absence from database failure", async () => {
  assertEquals(
    await fetchScanRecord(
      crypto.randomUUID(),
      scanLookupClient({ data: null, error: null }),
    ),
    null,
  );
  await assertRejects(
    () =>
      fetchScanRecord(
        crypto.randomUUID(),
        scanLookupClient({ data: null, error: { message: "unavailable" } }),
      ),
    Error,
    "Failed to fetch the canonical scan",
  );
});
