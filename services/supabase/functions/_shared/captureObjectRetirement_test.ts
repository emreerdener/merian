import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { R2Config } from "./aws.ts";
import {
  captureObjectBackendDigest,
  captureRetirementHealth,
  reconcileCaptureObjectRetirements,
} from "./captureObjectRetirement.ts";

const config = {
  endpoint: "https://storage.invalid",
  bucketName: "synthetic",
} as R2Config;
const owner = "00000000-0000-4000-8000-000000000001";
const objectKey = `staging/${owner}/fixture.webp`;
async function fixture(
  options: {
    status?: number;
    backend?: string;
    ack?: boolean;
    failure?: boolean;
    malformed?: boolean;
  } = {},
) {
  const events: string[] = [];
  const observations: Record<string, unknown>[] = [];
  const row = {
    backend_sha256: options.backend ?? await captureObjectBackendDigest(config),
    object_key: objectKey,
    owner_id: owner,
    issued_until: "2026-11-20T04:00:00Z",
  };
  const client = {
    rpc: (name: string, args: Record<string, unknown>) => {
      if (name === "claim_capture_object_retirements") {
        return {
          data: options.malformed
            ? [row, { ...row, object_key: "public_uploads/foreign" }]
            : [row],
          error: null,
        };
      }
      observations.push(args);
      events.push("observe");
      return { data: options.ack ?? true, error: null };
    },
  } as unknown as SupabaseClient;
  const run = () =>
    reconcileCaptureObjectRetirements(client, {
      config,
      now: () => 0,
      deleteObject: () => {
        events.push("delete");
        if (options.failure) throw new Error("synthetic failure");
        return Promise.resolve();
      },
      headObject: () => {
        events.push("head");
        return Promise.resolve(
          new Response(null, { status: options.status ?? 404 }),
        );
      },
    });
  return { run, events, observations };
}

Deno.test("retirement deletes then observes absence but retains unresolved obligation", async () => {
  const f = await fixture();
  assertEquals(await f.run(), {
    claimed: 1,
    observedAbsent: 1,
    deferred: 0,
    unresolved: 1,
  });
  assertEquals(f.events, ["delete", "head", "observe"]);
  assertEquals(f.observations[0].p_absent, true);
  assertEquals(f.observations[0].p_error, null);
});
Deno.test("retirement never sends object I/O to a different backend", async () => {
  const f = await fixture({ backend: "b".repeat(64) });
  assertEquals((await f.run()).deferred, 1);
  assertEquals(f.events, ["observe"]);
  assertEquals(f.observations[0].p_error, "backend_unavailable");
});
Deno.test("retirement validates whole claim batch before any object I/O", async () => {
  const f = await fixture({ malformed: true });
  await assertRejects(f.run);
  assertEquals(f.events, []);
});
for (const status of [200, 403, 500]) {
  Deno.test(`retirement HEAD ${status} cannot certify absence`, async () => {
    const f = await fixture({ status });
    assertEquals((await f.run()).observedAbsent, 0);
    assertEquals(f.observations[0].p_error, "object_io_failed");
  });
}
Deno.test("retirement I/O failure and lost acknowledgement remain deferred", async () => {
  for (const options of [{ failure: true }, { ack: false }]) {
    const f = await fixture(options);
    assertEquals((await f.run()).deferred, 1);
  }
});
Deno.test("retirement health fails closed and strips unexpected identity data", async () => {
  const data = {
    unresolved_count: 2,
    due_count: 1,
    leased_count: 0,
    error_count: 1,
    oldest_retired_age_seconds: 60,
    private_key: "must not escape",
  };
  const client = {
    rpc: () => Promise.resolve({ data, error: null }),
  } as unknown as SupabaseClient;
  assertEquals(await captureRetirementHealth(client), {
    unresolved_count: 2,
    due_count: 1,
    leased_count: 0,
    error_count: 1,
    oldest_retired_age_seconds: 60,
  });
  data.due_count = -1;
  await assertRejects(() => captureRetirementHealth(client));
});
