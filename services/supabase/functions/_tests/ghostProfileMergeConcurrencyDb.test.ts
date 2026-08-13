import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { insertUser } from "./exploreDbTestHelpers.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const CONFIGURED_DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL");
const DB_URL = CONFIGURED_DB_URL ?? DEFAULT_DB_URL;

type Settled =
  | { ok: true }
  | { ok: false; error: unknown };

function settle(promise: Promise<unknown>): Promise<Settled> {
  return promise.then(
    () => ({ ok: true }),
    (error: unknown) => ({ ok: false, error }),
  );
}

function describeError(error: unknown): string {
  return error instanceof Error
    ? `${error.name}: ${error.message}`
    : String(error);
}

function describeSettled(result: Settled): string {
  return result.ok
    ? "query unexpectedly succeeded"
    : describeError(result.error);
}

async function rollback(client: Client): Promise<void> {
  try {
    await client.queryArray("ROLLBACK");
  } catch {
    // A cleanup rollback is best-effort after a deliberately failed query.
  }
}

async function connectClients(
  label: string,
  count: number,
): Promise<Client[] | null> {
  const clients: Client[] = [];
  try {
    for (let index = 0; index < count; index += 1) {
      const client = new Client(DB_URL);
      await client.connect();
      clients.push(client);
    }
    return clients;
  } catch (error) {
    await Promise.all(clients.map((client) => client.end().catch(() => {})));
    const message = describeError(error);
    if (CONFIGURED_DB_URL != null) {
      throw new Error(
        `[${label}] Could not connect to configured DB integration test database ${DB_URL}: ${message}`,
        { cause: error },
      );
    }

    console.warn(
      `[${label}] Skipping DB integration test. Could not connect to ${DB_URL}: ${message}`,
    );
    return null;
  }
}

async function hasForwardHardening(
  client: Client,
  label: string,
): Promise<boolean> {
  const result = await client.queryObject<{
    revenuecat_definition: string | null;
    community_definition: string | null;
  }>(`
    SELECT
      pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
          'public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamptz)'
        )
      ) AS revenuecat_definition,
      pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
          'internal.merge_ghost_community_activity_actors(uuid,uuid)'
        )
      ) AS community_definition
  `);
  const revenuecatDefinition = result.rows[0]?.revenuecat_definition
    ?.replace(/\s+/g, " ")
    .toLowerCase() ?? "";
  const communityDefinition = result.rows[0]?.community_definition
    ?.replace(/\s+/g, " ")
    .toLowerCase() ?? "";
  const revenuecatUserLock = revenuecatDefinition.indexOf(
    "from public.users as users where users.id = p_user_id for update",
  );
  const revenuecatQueueLock = revenuecatDefinition.indexOf(
    "from internal.revenuecat_reconciliation_queue as queue where queue.merian_user_id = p_user_id and queue.claim_token = p_claim_token and queue.claim_expires_at > pg_catalog.clock_timestamp() for update",
  );
  const installed = revenuecatUserLock >= 0 &&
    revenuecatQueueLock > revenuecatUserLock &&
    revenuecatDefinition.includes("revenuecat_reconciliation_claim_lost") &&
    !communityDefinition.includes(
      "insert into internal.community_identification_activity_actors",
    );
  if (!installed && CONFIGURED_DB_URL != null) {
    throw new Error(
      `[${label}] The configured database has not applied Ghost merge forward hardening`,
    );
  }
  if (!installed) {
    console.warn(
      `[${label}] Skipping DB integration test because the local database has not applied Ghost merge forward hardening`,
    );
  }
  return installed;
}

async function setApplicationName(
  client: Client,
  applicationName: string,
): Promise<void> {
  await client.queryArray(
    "SELECT pg_catalog.SET_CONFIG('application_name', $1, FALSE)",
    [applicationName],
  );
}

async function backendPid(client: Client): Promise<number> {
  const result = await client.queryObject<{ pid: number }>(
    "SELECT pg_catalog.PG_BACKEND_PID() AS pid",
  );
  return result.rows[0].pid;
}

async function waitUntilBlocked(
  observer: Client,
  applicationName: string,
  blockerPid: number,
): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const result = await observer.queryObject<{ blocked: boolean }>(
      `
        SELECT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_stat_activity AS activity
          WHERE activity.application_name = $1
            AND activity.wait_event_type = 'Lock'
            AND $2::INTEGER = ANY(
              pg_catalog.PG_BLOCKING_PIDS(activity.pid)
            )
        ) AS blocked
      `,
      [applicationName, blockerPid],
    );
    if (result.rows[0].blocked) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }

  throw new Error(
    `${applicationName} did not reach the required blocked lock state`,
  );
}

async function configureTransaction(client: Client): Promise<void> {
  await client.queryArray("BEGIN");
  // lock_timeout bounds a regressed schedule without requiring elevated SET
  // privileges for deadlock_timeout on the disposable database role.
  await client.queryArray(
    "SELECT pg_catalog.SET_CONFIG('lock_timeout', '4s', TRUE)",
  );
}

async function cleanupUsers(
  client: Client,
  sourceUserId: string,
  targetUserId: string,
): Promise<void> {
  await client.queryArray(
    "DELETE FROM public.users WHERE id IN ($1::UUID, $2::UUID)",
    [sourceUserId, targetUserId],
  );
  await client.queryArray(
    "DELETE FROM auth.users WHERE id IN ($1::UUID, $2::UUID)",
    [sourceUserId, targetUserId],
  );
}

Deno.test("Ghost merge concurrency DB - RevenueCat parent lock displaces stale apply claim", async () => {
  const clients = await connectClients(
    "ghostProfileMergeConcurrencyDb.revenuecat",
    3,
  );
  if (clients == null) return;

  const [observer, mergeClient, applyClient] = clients;
  if (
    !(await hasForwardHardening(
      observer,
      "ghostProfileMergeConcurrencyDb.revenuecat",
    ))
  ) {
    await Promise.all(clients.map((client) => client.end()));
    return;
  }

  const suffix = crypto.randomUUID().slice(0, 8);
  const sourceUserId = crypto.randomUUID();
  const targetUserId = crypto.randomUUID();
  const claimToken = crypto.randomUUID();
  const applyApplicationName = `ghost-rc-apply-${suffix}`;
  let applyResult: Settled | null = null;
  let mergeFailure: unknown = null;

  try {
    await insertUser(observer, sourceUserId, `RC Source ${suffix}`);
    await insertUser(observer, targetUserId, `RC Target ${suffix}`);
    await observer.queryArray(
      `
        DELETE FROM internal.revenuecat_reconciliation_queue
        WHERE merian_user_id IN ($1::UUID, $2::UUID)
      `,
      [sourceUserId, targetUserId],
    );
    await observer.queryArray(
      `
        INSERT INTO internal.revenuecat_reconciliation_queue (
          merian_user_id,
          lookup_app_user_id,
          next_reconcile_at,
          attempt_count,
          claim_token,
          claimed_at,
          claim_expires_at,
          last_error_code
        )
        VALUES (
          $1::UUID,
          $1::UUID::TEXT,
          pg_catalog.NOW() + INTERVAL '10 days',
          2,
          $2::UUID,
          pg_catalog.NOW(),
          pg_catalog.NOW() + INTERVAL '10 minutes',
          'concurrency_fixture'
        )
      `,
      [targetUserId, claimToken],
    );

    await setApplicationName(applyClient, applyApplicationName);
    await configureTransaction(mergeClient);
    await configureTransaction(applyClient);
    const mergePid = await backendPid(mergeClient);

    await mergeClient.queryArray(
      `
        SELECT profile.id
        FROM public.users AS profile
        WHERE profile.id IN ($1::UUID, $2::UUID)
        ORDER BY profile.id
        FOR UPDATE
      `,
      [sourceUserId, targetUserId],
    );

    const applyPromise = settle(
      applyClient.queryArray(
        `
          SELECT public.apply_revenuecat_reconciliation(
            $1::UUID,
            $2::UUID,
            999,
            'pro',
            NULL
          )
        `,
        [targetUserId, claimToken],
      ),
    );
    await waitUntilBlocked(
      observer,
      applyApplicationName,
      mergePid,
    );

    try {
      await mergeClient.queryArray(
        `SELECT internal.merge_ghost_revenuecat_state($1::UUID, $2::UUID)`,
        [sourceUserId, targetUserId],
      );
      await mergeClient.queryArray("COMMIT");
    } catch (error) {
      mergeFailure = error;
      await rollback(mergeClient);
    }

    applyResult = await applyPromise;
    await rollback(applyClient);

    assertEquals(
      mergeFailure,
      null,
      `RevenueCat merge-side repair failed: ${describeError(mergeFailure)}`,
    );
    assert(
      applyResult != null && !applyResult.ok,
      "the displaced RevenueCat apply claim must fail",
    );
    assertStringIncludes(
      describeError(applyResult.error),
      "revenuecat_reconciliation_claim_lost",
    );

    const state = await observer.queryObject<{
      lookup_app_user_id: string;
      due_now: boolean;
      claim_token: string | null;
      subscription_tier: string;
      customer_state_exists: boolean;
    }>(
      `
        SELECT
          queue.lookup_app_user_id,
          queue.next_reconcile_at <= pg_catalog.NOW() AS due_now,
          queue.claim_token::TEXT,
          app_user.subscription_tier::TEXT,
          EXISTS (
            SELECT 1
            FROM internal.revenuecat_customer_state AS customer_state
            WHERE customer_state.merian_user_id = app_user.id
          ) AS customer_state_exists
        FROM public.users AS app_user
        JOIN internal.revenuecat_reconciliation_queue AS queue
          ON queue.merian_user_id = app_user.id
        WHERE app_user.id = $1::UUID
      `,
      [targetUserId],
    );
    assertEquals(state.rows.length, 1);
    assertEquals(
      state.rows[0].lookup_app_user_id,
      targetUserId.toUpperCase(),
    );
    assert(state.rows[0].due_now);
    assertEquals(state.rows[0].claim_token, null);
    assertEquals(state.rows[0].subscription_tier, "free");
    assertEquals(state.rows[0].customer_state_exists, false);
  } finally {
    await rollback(mergeClient);
    await rollback(applyClient);
    await cleanupUsers(observer, sourceUserId, targetUserId).catch(() => {});
    await Promise.all(clients.map((client) => client.end().catch(() => {})));
  }
});

Deno.test("Ghost merge concurrency DB - Community handler takes no group lock after actor lock", async () => {
  const clients = await connectClients(
    "ghostProfileMergeConcurrencyDb.community",
    3,
  );
  if (clients == null) return;

  const [observer, mergeClient, writerClient] = clients;
  if (
    !(await hasForwardHardening(
      observer,
      "ghostProfileMergeConcurrencyDb.community",
    ))
  ) {
    await Promise.all(clients.map((client) => client.end()));
    return;
  }

  const suffix = crypto.randomUUID().slice(0, 8);
  const sourceUserId = crypto.randomUUID();
  const targetUserId = crypto.randomUUID();
  const scanId = crypto.randomUUID();
  const postId = crypto.randomUUID();
  const requestId = crypto.randomUUID();
  const activityGroupId = crypto.randomUUID();
  const writerApplicationName = `ghost-community-writer-${suffix}`;
  let mergeFailure: unknown = null;
  let writerResult: Settled | null = null;

  try {
    await insertUser(observer, sourceUserId, `Actor Source ${suffix}`);
    await insertUser(observer, targetUserId, `Actor Target ${suffix}`);
    await observer.queryArray(
      `
        INSERT INTO public.scans (
          id,
          user_id,
          species_id,
          ai_confidence_score
        )
        VALUES ($1::UUID, $2::UUID, NULL, 0.8)
      `,
      [scanId, sourceUserId],
    );
    await observer.queryArray(
      `
        INSERT INTO public.explore_posts (id, user_id, scan_id)
        VALUES ($1::UUID, $2::UUID, $3::UUID)
      `,
      [postId, sourceUserId, scanId],
    );
    await observer.queryArray(
      `
        INSERT INTO public.explore_community_requests (
          id,
          post_id,
          scan_id,
          requested_by
        )
        VALUES ($1::UUID, $2::UUID, $3::UUID, $4::UUID)
      `,
      [requestId, postId, scanId, sourceUserId],
    );
    await observer.queryArray(
      `
        INSERT INTO internal.community_identification_activity_groups (
          id,
          request_id,
          post_id,
          request_generation_at,
          activity_type,
          burst_started_at,
          activity_at
        )
        VALUES (
          $1::UUID,
          $2::UUID,
          $3::UUID,
          pg_catalog.NOW() - INTERVAL '2 hours',
          'suggestion_burst',
          pg_catalog.NOW() - INTERVAL '90 minutes',
          pg_catalog.NOW() - INTERVAL '60 minutes'
        )
      `,
      [activityGroupId, requestId, postId],
    );
    await observer.queryArray(
      `
        INSERT INTO internal.community_identification_activity_actors (
          activity_group_id,
          user_id,
          suggestion_count,
          last_suggested_at
        )
        VALUES ($1::UUID, $2::UUID, 1, pg_catalog.NOW())
      `,
      [activityGroupId, sourceUserId],
    );

    await setApplicationName(writerClient, writerApplicationName);
    await configureTransaction(mergeClient);
    await configureTransaction(writerClient);
    const mergePid = await backendPid(mergeClient);

    await mergeClient.queryArray(
      `
        SELECT profile.id
        FROM public.users AS profile
        WHERE profile.id IN ($1::UUID, $2::UUID)
        ORDER BY profile.id
        FOR UPDATE
      `,
      [sourceUserId, targetUserId],
    );
    await mergeClient.queryArray(
      `
        SELECT actor.user_id
        FROM internal.community_identification_activity_actors AS actor
        WHERE actor.activity_group_id = $1::UUID
          AND actor.user_id = $2::UUID
        FOR UPDATE
      `,
      [activityGroupId, sourceUserId],
    );

    await writerClient.queryArray(
      `
        SELECT activity_group.id
        FROM internal.community_identification_activity_groups
          AS activity_group
        WHERE activity_group.id = $1::UUID
        FOR UPDATE
      `,
      [activityGroupId],
    );
    const writerPromise = settle(
      writerClient.queryArray(
        `
          UPDATE internal.community_identification_activity_actors
          SET suggestion_count = suggestion_count + 1,
              last_suggested_at = pg_catalog.NOW()
          WHERE activity_group_id = $1::UUID
            AND user_id = $2::UUID
        `,
        [activityGroupId, sourceUserId],
      ),
    );
    await waitUntilBlocked(
      observer,
      writerApplicationName,
      mergePid,
    );

    try {
      await mergeClient.queryArray(
        `
          SELECT internal.merge_ghost_community_activity_actors(
            $1::UUID,
            $2::UUID
          )
        `,
        [sourceUserId, targetUserId],
      );
      await mergeClient.queryArray("COMMIT");
    } catch (error) {
      mergeFailure = error;
      await rollback(mergeClient);
    }

    writerResult = await writerPromise;
    if (writerResult.ok) {
      await writerClient.queryArray("COMMIT");
    } else {
      await rollback(writerClient);
    }

    assertEquals(
      mergeFailure,
      null,
      `Community merge-side handler failed: ${describeError(mergeFailure)}`,
    );
    assert(
      writerResult.ok,
      `Community writer failed: ${describeSettled(writerResult)}`,
    );

    const actors = await observer.queryObject<{
      user_id: string;
      suggestion_count: number;
    }>(
      `
        SELECT actor.user_id::TEXT, actor.suggestion_count
        FROM internal.community_identification_activity_actors AS actor
        WHERE actor.activity_group_id = $1::UUID
        ORDER BY actor.user_id
      `,
      [activityGroupId],
    );
    assertEquals(actors.rows, [{
      user_id: sourceUserId,
      suggestion_count: 2,
    }]);
  } finally {
    await rollback(mergeClient);
    await rollback(writerClient);
    await cleanupUsers(observer, sourceUserId, targetUserId).catch(() => {});
    await Promise.all(clients.map((client) => client.end().catch(() => {})));
  }
});
