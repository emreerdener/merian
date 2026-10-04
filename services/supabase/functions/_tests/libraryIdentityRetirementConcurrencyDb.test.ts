import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const databaseUrl = Deno.env.get("SUPABASE_DB_TEST_URL");
Deno.test({
  name:
    "Library identity DB - merge commit fences a waiting stale ingestion claim",
  ignore: !databaseUrl,
  async fn() {
    assert(databaseUrl);
    assert(
      ["127.0.0.1", "localhost", "[::1]"].includes(
        new URL(databaseUrl).hostname,
      ),
    );
    const clients = [
      new Client(databaseUrl),
      new Client(databaseUrl),
      new Client(databaseUrl),
    ];
    const [observer, merger, ingestion] = clients;
    const source = crypto.randomUUID(),
      target = crypto.randomUUID(),
      scan = crypto.randomUUID();
    let pending: Promise<{ ok: boolean; code?: string }> | undefined;
    try {
      for (const client of clients) await client.connect();
      await observer.queryArray(
        "INSERT INTO auth.users(id,aud,role,is_anonymous) VALUES ($1,'authenticated','authenticated',TRUE),($2,'authenticated','authenticated',FALSE)",
        [source, target],
      );
      await observer.queryArray(
        "INSERT INTO public.users(id,public_author_name,public_identity_source,public_username) VALUES ($1,'Fixture source','alias',$3),($2,'Fixture target','alias',$4) ON CONFLICT(id) DO NOTHING",
        [
          source,
          target,
          `lib_${source.replaceAll("-", "").slice(0, 12)}`,
          `lib_${target.replaceAll("-", "").slice(0, 12)}`,
        ],
      );
      await merger.queryArray("BEGIN");
      await merger.queryArray(
        "SELECT internal.perform_ghost_profile_merge($1,$2)",
        [source, target],
      );
      await ingestion.queryArray("BEGIN");
      await ingestion.queryArray("SET LOCAL ROLE service_role");
      await ingestion.queryArray(
        "SELECT set_config('request.jwt.claims','{\"role\":\"service_role\"}',TRUE)",
      );
      const mergerPID = (await merger.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() AS pid",
      )).rows[0].pid;
      const ingestionPID = (await ingestion.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() AS pid",
      )).rows[0].pid;
      pending = ingestion.queryArray(
        "SELECT public.claim_scan_ingestion_job($1,$2,'identify-multimodal')",
        [scan, source],
      ).then(
        () => ({ ok: true }),
        (error) => ({ ok: false, code: error.fields?.code }),
      );
      let blocked = false;
      for (let n = 0; n < 100; n++) {
        const rows = await observer.queryObject<{ blocked: boolean }>(
          "SELECT $1::int = ANY(pg_blocking_pids($2::int)) AS blocked",
          [mergerPID, ingestionPID],
        );
        if (rows.rows[0].blocked) {
          blocked = true;
          break;
        }
        await new Promise((resolve) => setTimeout(resolve, 20));
      }
      assert(blocked, "Ingestion must wait on the merge's profile lock");
      await merger.queryArray("COMMIT");
      assertEquals(await pending, { ok: false, code: "P0002" });
      await ingestion.queryArray("ROLLBACK");
      const result = await observer.queryObject<{ count: number }>(
        "SELECT count(*)::int AS count FROM public.scan_ingestion_jobs WHERE user_id=$1",
        [source],
      );
      assertEquals(result.rows[0].count, 0);
    } finally {
      await merger.queryArray("ROLLBACK").catch(() => {});
      await pending?.catch(() => {});
      await ingestion.queryArray("ROLLBACK").catch(() => {});
      await observer.queryArray("DELETE FROM auth.users WHERE id IN ($1,$2)", [
        source,
        target,
      ]).catch(() => {});
      for (const client of clients) await client.end();
    }
  },
});
