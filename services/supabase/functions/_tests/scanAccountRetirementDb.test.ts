import { assert, assertEquals, assertRejects } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

Deno.test({
  name: "scan insertion and account retirement serialize at the actual write",
  ignore: !Deno.env.get("SUPABASE_DB_TEST_URL"),
  async fn() {
    const url = Deno.env.get("SUPABASE_DB_TEST_URL");
    assert(
      url &&
        ["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname),
    );
    const setup = new Client(url),
      writer = new Client(url),
      retirement = new Client(url);
    await Promise.all([
      setup.connect(),
      writer.connect(),
      retirement.connect(),
    ]);
    const owner = crypto.randomUUID(), scan = crypto.randomUUID();
    const insert = (connection: Client, id = scan) =>
      connection.queryArray(
        "INSERT INTO public.scans(id,user_id,ai_confidence_score,is_biological_subject,inference_tier) VALUES($1,$2,0.2,false,'flash') ON CONFLICT(id) DO NOTHING",
        [id, owner],
      );
    try {
      await setup.queryArray(
        "INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) VALUES($1::uuid,'authenticated','authenticated',$1::uuid::text||'@example.invalid','{}','{}',now(),now())",
        [owner],
      );
      // Retirement-first, still uncommitted: an insert must fail promptly rather
      // than wait behind an intake transaction that can also need its user row.
      await retirement.queryArray("BEGIN; SET LOCAL statement_timeout='5s'");
      await retirement.queryArray(
        "INSERT INTO internal.account_deletion_jobs(user_id) VALUES($1)",
        [owner],
      );
      await assertRejects(
        () => insert(writer),
        Error,
        "capture_owner_unavailable",
      );
      await retirement.queryArray("ROLLBACK");
      assertEquals(
        (await setup.queryObject("SELECT id FROM public.scans WHERE id=$1", [
          scan,
        ])).rows,
        [],
      );

      // Insert-first: intake waits for that exact write transaction, then its
      // normal cleanup can include the already committed scan.
      await writer.queryArray("BEGIN; SET LOCAL statement_timeout='5s'");
      await insert(writer);
      await retirement.queryArray("BEGIN; SET LOCAL statement_timeout='5s'");
      const pid = (await retirement.queryObject<{ pid: number }>(
        "SELECT pg_backend_pid() pid",
      )).rows[0].pid;
      let finished = false;
      const intake = retirement.queryArray(
        "INSERT INTO internal.account_deletion_jobs(user_id) VALUES($1)",
        [owner],
      ).finally(() => {
        finished = true;
      });
      let blocked = false;
      for (let attempt = 0; attempt < 100 && !finished; attempt++) {
        blocked = (await setup.queryObject<{ blocked: boolean }>(
          "SELECT cardinality(pg_blocking_pids($1))>0 blocked",
          [pid],
        )).rows[0].blocked;
        if (blocked) break;
        await new Promise((resolve) => setTimeout(resolve, 10));
      }
      assert(blocked, "account intake must wait for the scan insertion fence");
      await writer.queryArray("COMMIT");
      await intake;
      await retirement.queryArray("COMMIT");
      await assertRejects(
        () => insert(writer),
        Error,
        "capture_owner_unavailable",
      );
      await assertRejects(
        () => insert(writer, crypto.randomUUID()),
        Error,
        "capture_owner_unavailable",
      );
      assertEquals(
        (await setup.queryObject<{ n: number }>(
          "SELECT count(*)::int n FROM public.scans WHERE user_id=$1",
          [owner],
        )).rows[0].n,
        1,
      );
    } finally {
      await writer.queryArray("ROLLBACK").catch(() => {});
      await retirement.queryArray("ROLLBACK").catch(() => {});
      await setup.queryArray("DELETE FROM public.scans WHERE id=$1", [scan]);
      await setup.queryArray("DELETE FROM public.users WHERE id=$1", [owner]);
      await setup.queryArray("DELETE FROM auth.users WHERE id=$1", [owner]);
      await setup.queryArray(
        "DELETE FROM internal.account_deletion_jobs WHERE user_id=$1",
        [owner],
      );
      await Promise.all([setup.end(), writer.end(), retirement.end()]);
    }
  },
});
