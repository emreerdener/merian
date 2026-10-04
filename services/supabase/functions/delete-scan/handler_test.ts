import { assertEquals } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { handleScanDeletion } from "./handler.ts";

Deno.test("legacy history deletion stops before media lookup, erasure and completion", async () => {
  const calls: string[] = [];
  const client = {
    rpc(name: string) {
      calls.push(name);
      if (name !== "request_scan_deletion") {
        throw new Error("Unexpected erasure completion");
      }
      return Promise.resolve({
        data: "legacy_observation_delete_requires_upgrade",
        error: null,
      });
    },
    from() {
      throw new Error("Legacy rejection must not reach media discovery");
    },
  } as unknown as SupabaseClient;
  const response = await handleScanDeletion(
    "00000000-0000-4000-8000-00000000d203",
    "00000000-0000-4000-8000-00000000d204",
    client,
  );
  assertEquals(response.status, 409);
  assertEquals(await response.json(), {
    error: "Update Merian to review and delete this saved scan.",
    code: "legacy_observation_delete_requires_upgrade",
  });
  assertEquals(calls, ["request_scan_deletion"]);
});
