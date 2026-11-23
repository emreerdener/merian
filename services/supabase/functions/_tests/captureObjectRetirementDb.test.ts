import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { R2Config } from "../_shared/aws.ts";
import {
  captureObjectBackendDigest,
  captureRetirementHealth,
  reconcileCaptureObjectRetirements,
} from "../_shared/captureObjectRetirement.ts";

const databaseURL = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "capture retirement survives account rows and repeated late PUTs after observed absence",
  ignore: !databaseURL,
  async fn() {
    assert(databaseURL);
    assert(
      ["localhost", "127.0.0.1", "[::1]"].includes(
        new URL(databaseURL).hostname,
      ),
    );
    const db = new Client(databaseURL);
    const owner = crypto.randomUUID();
    const key = `staging/${owner}/retirement.webp`;
    const config = {
      endpoint: "https://capture-fixture.invalid",
      bucketName: "synthetic",
    } as R2Config;
    const backend = await captureObjectBackendDigest(config);
    await db.connect();
    try {
      await db.queryArray("BEGIN");
      await db.queryArray("SET LOCAL statement_timeout='10s'");
      await db.queryArray(
        "SELECT set_config('request.jwt.claim.role','service_role',true)",
      );
      await db.queryArray(
        "INSERT INTO auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1,'authenticated','authenticated','{}','{}',now(),now())",
        [owner],
      );
      const registration = await db.queryObject<{ saved: boolean }>(
        "SELECT public.register_capture_upload_capabilities($1,$2,jsonb_build_array(jsonb_build_object('object_key',$3::text,'expires_at',clock_timestamp()+interval '1 hour','scan_id',NULL,'asset_id',NULL,'session_id',NULL))) AS saved",
        [owner, backend, key],
      );
      assertEquals(registration.rows[0].saved, true);
      await db.queryArray("SELECT * FROM public.request_account_deletion($1)", [
        owner,
      ]);
      await db.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
      await db.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);

      // Exercise the production worker against the real RPC implementation.
      // Only object transport is synthetic; there are no external R2 requests.
      const client = {
        rpc: async (name: string, args: Record<string, unknown> = {}) => {
          if (name === "claim_capture_object_retirements") {
            const result = await db.queryObject<
              {
                backend_sha256: string;
                object_key: string;
                owner_id: string;
                issued_until: Date;
              }
            >("SELECT * FROM public.claim_capture_object_retirements($1,$2)", [
              args.p_token,
              args.p_limit,
            ]);
            return {
              data: result.rows.map((r) => ({
                ...r,
                issued_until: r.issued_until.toISOString(),
              })),
              error: null,
            };
          }
          if (name === "observe_capture_object_retirement") {
            const result = await db.queryObject<{ saved: boolean }>(
              "SELECT public.observe_capture_object_retirement($1,$2,$3,$4,$5) AS saved",
              [
                args.p_backend,
                args.p_key,
                args.p_token,
                args.p_absent,
                args.p_error,
              ],
            );
            return { data: result.rows[0].saved, error: null };
          }
          assertEquals(name, "capture_object_retirement_health");
          const result = await db.queryObject<{ value: unknown }>(
            "SELECT public.capture_object_retirement_health() AS value",
          );
          return { data: result.rows[0].value, error: null };
        },
      } as unknown as SupabaseClient;
      let present = true, injectLateWrite = true, deletes = 0;
      const io = {
        config,
        deleteObject: (objectKey: string) => {
          assertEquals(objectKey, key);
          deletes++;
          present = injectLateWrite;
          injectLateWrite = false;
          return Promise.resolve();
        },
        headObject: (objectKey: string) => {
          assertEquals(objectKey, key);
          return Promise.resolve(
            new Response(null, { status: present ? 200 : 404 }),
          );
        },
      };
      const first = await reconcileCaptureObjectRetirements(client, io);
      assertEquals(first, {
        claimed: 1,
        observedAbsent: 0,
        deferred: 1,
        unresolved: 1,
      });
      assertEquals((await captureRetirementHealth(client)).error_count, 1);
      for (let pass = 0; pass < 2; pass++) {
        // Simulate a later scheduled pass, and an issued PUT finishing after
        // the prior pass's negative HEAD. Neither event recreates row owners.
        present = true;
        await db.queryArray(
          "UPDATE internal.capture_object_authorities SET next_check_at=clock_timestamp()-interval '1 second' WHERE backend_sha256=$1 AND object_key=$2",
          [backend, key],
        );
        assertEquals(await reconcileCaptureObjectRetirements(client, io), {
          claimed: 1,
          observedAbsent: 1,
          deferred: 0,
          unresolved: 1,
        });
        const result = await db.queryObject<{ retained: boolean }>(
          "SELECT retired_at IS NOT NULL AND observed_absent_at IS NOT NULL AND claim_token IS NULL AND next_check_at>clock_timestamp() AS retained FROM internal.capture_object_authorities WHERE backend_sha256=$1 AND object_key=$2",
          [backend, key],
        );
        assertEquals(result.rows[0].retained, true);
      }
      assertEquals(deletes, 3);
      assertEquals(present, false);
      assertEquals((await captureRetirementHealth(client)).unresolved_count, 1);
    } finally {
      await db.queryArray("ROLLBACK");
      await db.end();
    }
  },
});
