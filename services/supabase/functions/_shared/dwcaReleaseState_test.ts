import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  fetchDwcaExportReleaseState,
  parseDwcaExportReleaseState,
} from "./dwcaReleaseState.ts";

Deno.test("DwC-A release state accepts only an explicit database boolean", () => {
  assertEquals(parseDwcaExportReleaseState({ enabled: false }), {
    enabled: false,
  });
  assertEquals(parseDwcaExportReleaseState({ enabled: true }), {
    enabled: true,
  });
  assertThrows(() => parseDwcaExportReleaseState({}));
  assertThrows(() => parseDwcaExportReleaseState({ enabled: "false" }));
  assertThrows(() => parseDwcaExportReleaseState(null));
});

Deno.test("DwC-A release-state lookup uses the service-only RPC and fails closed", async () => {
  let routineName = "";
  const client = {
    rpc(name: string) {
      routineName = name;
      return Promise.resolve({ data: { enabled: false }, error: null });
    },
  } as unknown as SupabaseClient;

  assertEquals(await fetchDwcaExportReleaseState(client), { enabled: false });
  assertEquals(routineName, "get_dwca_export_release_state");

  await assertRejects(
    () =>
      fetchDwcaExportReleaseState({
        rpc() {
          return Promise.resolve({
            data: null,
            error: { message: "offline" },
          });
        },
      } as unknown as SupabaseClient),
    Error,
    "unavailable",
  );
});
