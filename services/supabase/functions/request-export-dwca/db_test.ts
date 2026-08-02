import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { requestDwcaExportJob } from "./db.ts";

const userId = "00000000-0000-4000-8000-000000000301";
const jobId = "00000000-0000-4000-8000-000000000302";

function client(data: unknown, error: unknown = null): SupabaseClient {
  return {
    rpc(name: string, args: Record<string, unknown>) {
      assertEquals(name, "request_dwca_export_job");
      assertEquals(args, {
        p_user_id: userId,
        p_export_scope: "personal",
        p_include_precise_coordinates: false,
      });
      return Promise.resolve({ data, error });
    },
  } as unknown as SupabaseClient;
}

Deno.test("DwC-A request maps every stable database disposition", async () => {
  for (
    const disposition of [
      "disabled",
      "rate_limited",
      "already_pending",
    ] as const
  ) {
    assertEquals(
      await requestDwcaExportJob(
        userId,
        "personal",
        false,
        client({ status: disposition }),
      ),
      disposition,
    );
  }
  assertEquals(
    await requestDwcaExportJob(
      userId,
      "personal",
      false,
      client({ status: "queued", job_id: jobId }),
    ),
    "queued",
  );
});

Deno.test("DwC-A request fails closed on RPC and response-shape errors", async () => {
  await assertRejects(
    () =>
      requestDwcaExportJob(
        userId,
        "personal",
        false,
        client(null, { message: "offline" }),
      ),
    Error,
    "Failed to request",
  );
  await assertRejects(
    () =>
      requestDwcaExportJob(
        userId,
        "personal",
        false,
        client({ status: "queued", job_id: "not-a-uuid" }),
      ),
    Error,
    "identifier is invalid",
  );
  await assertRejects(
    () =>
      requestDwcaExportJob(
        userId,
        "personal",
        false,
        client({ status: "unexpected" }),
      ),
    Error,
    "unknown result",
  );
});
