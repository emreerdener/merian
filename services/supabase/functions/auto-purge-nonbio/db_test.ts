import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

import { requestNonBiologicalScanRetentionDeletions } from "./db.ts";

function clientReturning(
  data: unknown,
  error: unknown = null,
  capture?: (name: string, parameters: unknown) => void,
): SupabaseClient {
  return {
    rpc(name: string, parameters: unknown) {
      capture?.(name, parameters);
      return Promise.resolve({ data, error });
    },
  } as unknown as SupabaseClient;
}

Deno.test("retention request accepts only the bounded integer RPC result", async () => {
  let invocation: { name: string; parameters: unknown } | null = null;
  const result = await requestNonBiologicalScanRetentionDeletions(
    500,
    clientReturning(17, null, (name, parameters) => {
      invocation = { name, parameters };
    }),
  );

  assertEquals(result, 17);
  assertEquals(invocation, {
    name: "request_nonbiological_scan_retention_deletions",
    parameters: { p_limit: 500 },
  });
});

Deno.test("retention request rejects invalid local and remote bounds", async () => {
  await assertRejects(
    () =>
      requestNonBiologicalScanRetentionDeletions(
        0,
        clientReturning(0),
      ),
    Error,
    "Invalid non-biological retention batch size.",
  );
  await assertRejects(
    () =>
      requestNonBiologicalScanRetentionDeletions(
        10,
        clientReturning(11),
      ),
    Error,
    "Failed to request non-biological scan retention deletions.",
  );
});

Deno.test("retention request fails closed on RPC errors and malformed data", async () => {
  for (
    const client of [
      clientReturning(null, { message: "database unavailable" }),
      clientReturning("1"),
      clientReturning(1.5),
    ]
  ) {
    await assertRejects(
      () => requestNonBiologicalScanRetentionDeletions(10, client),
      Error,
      "Failed to request non-biological scan retention deletions.",
    );
  }
});
