import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
const url = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "Gemini smoke ownership, release lock order and competing activation fail closed",
  ignore: !url,
  async fn() {
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const observer = new Client(url),
      first = new Client(url),
      second = new Client(url);
    const release = crypto.randomUUID();
    const activationRelease = crypto.randomUUID();
    try {
      for (const db of [observer, first, second]) {
        await db.connect();
        await db.queryArray("SET request.jwt.claim.role='service_role'");
        await db.queryArray("SET statement_timeout='8s'");
      }
      const source = await Deno.readTextFile(
        new URL("../../tests/gemini_release_lifecycle.sql", import.meta.url),
      );
      await observer.queryArray(
        source.slice(
          source.indexOf("CREATE FUNCTION pg_temp.release_manifest"),
          source.indexOf("CREATE TEMP TABLE test_release"),
        ),
      );
      const manifest = (await observer.queryObject<{ value: string }>(
        "SELECT pg_temp.release_manifest($1::uuid,replace($1::text,'-','')||'12345678') value",
        [release],
      )).rows[0].value;
      await observer.queryArray("SELECT internal.register_gemini_release($1)", [
        manifest,
      ]);
      const digest = (await observer.queryObject<{ value: string }>(
        "SELECT configuration_digest value FROM internal.gemini_activation_releases WHERE id=$1",
        [release],
      )).rows[0].value;
      const pid = (await second.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      const waitForLock = async () => {
        for (let n = 0; n < 100; n++) {
          const state = (await observer.queryObject<{ blocked: boolean }>(
            "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
            [pid],
          )).rows[0];
          if (state.blocked) return;
          await new Promise((resolve) => setTimeout(resolve, 10));
        }
        throw new Error("Expected a serialized database waiter");
      };
      await first.queryArray("BEGIN");
      const claim =
        (await first.queryObject<{ value: Record<string, unknown> }>(
          "SELECT public.claim_gemini_release_smoke($1,'case_1',$2) value",
          [release, digest],
        )).rows[0].value;
      assert(typeof claim.owner_token === "string");
      const repeated = second.queryObject<{ value: Record<string, unknown> }>(
        "SELECT public.claim_gemini_release_smoke($1,'case_1',$2) value",
        [release, digest],
      );
      await waitForLock();
      await first.queryArray("COMMIT");
      assertEquals((await repeated).rows[0].value, {
        state: "claimed",
        receipt: null,
      });
      await first.queryArray(
        "SELECT public.advance_gemini_release_smoke($1,'case_1',$2,'dispatch')",
        [release, claim.owner_token],
      );
      // Simulated crash/lost response: a new connection cannot own or pass it.
      const resumed =
        (await second.queryObject<{ value: Record<string, unknown> }>(
          "SELECT public.claim_gemini_release_smoke($1,'case_1',$2) value",
          [release, digest],
        )).rows[0].value;
      assertEquals(resumed.state, "dispatch_intent");
      assertEquals(resumed.owner_token, undefined);
      await first.queryArray("BEGIN");
      await first.queryArray(
        "SELECT revision FROM internal.gemini_routing_head WHERE singleton FOR UPDATE",
      );
      const registration = second.queryArray(
        "SELECT internal.register_gemini_release($1)",
        [manifest],
      );
      await waitForLock();
      // Activation's head -> release order must never deadlock against retry.
      await first.queryArray(
        "SELECT id FROM internal.gemini_activation_releases WHERE id=$1 FOR UPDATE",
        [release],
      );
      await first.queryArray("ROLLBACK");
      await registration;

      // Prepare a separate, fully verified synthetic release. All provider
      // receipts below are fixtures; no provider transport is available here.
      const activationManifest = (await observer.queryObject<{ value: string }>(
        "SELECT pg_temp.release_manifest($1::uuid,replace($1::text,'-','')||'12345678') value",
        [activationRelease],
      )).rows[0].value;
      await observer.queryArray("SELECT internal.register_gemini_release($1)", [
        activationManifest,
      ]);
      await observer.queryArray(
        "CREATE TEMP TABLE test_release(id uuid,manifest text)",
      );
      await observer.queryArray("INSERT INTO test_release VALUES($1,$2)", [
        activationRelease,
        activationManifest,
      ]);
      const receiptsStart = source.indexOf("DO $$");
      await observer.queryArray(
        source.slice(
          receiptsStart,
          source.indexOf("END $$;", receiptsStart) + 7,
        ),
      );
      await observer.queryArray(
        "SELECT internal.verify_gemini_release(id,(manifest::jsonb->>'configuration_text')::jsonb->'required_functions',(manifest::jsonb->>'configuration_text')::jsonb->'required_gates') FROM test_release",
      );
      const activate =
        "SELECT internal.activate_gemini_release($1::uuid,'synthetic_test',$2::jsonb->>'backend_sha',$2::jsonb->>'configuration_digest',($2::jsonb->>'configuration_text')::jsonb->'required_functions',($2::jsonb->>'configuration_text')::jsonb->'required_gates')";
      const before = (await observer.queryObject<{ revision: bigint }>(
        "SELECT revision FROM internal.gemini_routing_head",
      )).rows[0].revision;
      await first.queryArray("BEGIN");
      await first.queryArray(activate, [activationRelease, activationManifest]);
      await second.queryArray("SET statement_timeout='250ms'");
      const competing = second.queryArray(activate, [
        activationRelease,
        activationManifest,
      ]).then(
        () => {
          throw new Error("Competing activation crossed the held routing lock");
        },
        (error) => {
          assertEquals(error.fields?.code, "57014");
        },
      );
      await waitForLock();
      await competing;
      assertEquals(
        (await observer.queryObject<{ revision: bigint }>(
          "SELECT revision FROM internal.gemini_routing_head",
        )).rows[0].revision,
        before,
      );
      // Never leave candidate routing installed in the shared disposable DB.
      await first.queryArray("ROLLBACK");
    } finally {
      for (const db of [first, second]) {
        await db.queryArray("ROLLBACK").catch(() => {});
      }
      for (const ownedRelease of [release, activationRelease]) {
        await observer.queryArray(
          "DELETE FROM public.ai_usage_events WHERE source_type='gemini_release_smoke' AND source_id IN (SELECT owner_token FROM internal.gemini_release_smokes WHERE release_id=$1)",
          [ownedRelease],
        ).catch(() => {});
        await observer.queryArray(
          "DELETE FROM internal.gemini_release_events WHERE release_id=$1",
          [ownedRelease],
        ).catch(() => {});
        await observer.queryArray(
          "DELETE FROM internal.gemini_release_smokes WHERE release_id=$1",
          [ownedRelease],
        ).catch(() => {});
        await observer.queryArray(
          "DELETE FROM internal.gemini_activation_releases WHERE id=$1",
          [ownedRelease],
        ).catch(() => {});
      }
      for (const db of [observer, first, second]) {
        await db.end().catch(() => {});
      }
    }
  },
});
