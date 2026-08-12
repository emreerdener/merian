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

interface RolloutConfig {
  principal_mode: string;
  account_grant_mode: string;
}

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

async function rollback(client: Client): Promise<void> {
  try {
    await client.queryArray("ROLLBACK");
  } catch {
    // Best-effort cleanup after the deliberately rejected compatibility call.
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

async function hasCompatibilityLock(
  client: Client,
  label: string,
): Promise<boolean> {
  const result = await client.queryObject<{ installed: boolean }>(`
    SELECT
      pg_catalog.TO_REGPROCEDURE(
        'internal.lock_legacy_revenuecat_compatibility_users(uuid[])'
      ) IS NOT NULL
      AND pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
          'public.apply_revenuecat_customer_state(text,bigint,text,text,bigint,jsonb)'
        )
      ) LIKE '%lock_legacy_revenuecat_compatibility_users%'
        AS installed
  `);
  const installed = result.rows[0]?.installed === true;
  if (!installed && CONFIGURED_DB_URL != null) {
    throw new Error(
      `[${label}] The configured database lacks the legacy RevenueCat compatibility lock`,
    );
  }
  if (!installed) {
    console.warn(
      `[${label}] Skipping DB integration test because the compatibility lock is absent`,
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
    if (result.rows[0]?.blocked === true) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error(
    `${applicationName} did not reach the required blocked lock state`,
  );
}

async function beginTransaction(
  client: Client,
  asServiceRole = false,
): Promise<void> {
  await client.queryArray("BEGIN");
  await client.queryArray(
    "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
  );
  if (asServiceRole) {
    await client.queryArray("SET LOCAL ROLE service_role");
  }
}

Deno.test("purchase-principal compatibility DB - rebind wins before legacy mutation", async () => {
  const label = "purchasePrincipalCompatibilityConcurrencyDb.rebind";
  const clients = await connectClients(label, 4);
  if (clients == null) return;

  const [observer, userBlocker, completionClient, legacyClient] = clients;
  if (!(await hasCompatibilityLock(observer, label))) {
    await Promise.all(clients.map((client) => client.end()));
    return;
  }

  const suffix = crypto.randomUUID().slice(0, 8);
  const sourceUserId = crypto.randomUUID();
  const targetUserId = crypto.randomUUID();
  const capabilityHash = "a".repeat(56) + suffix;
  const eventId = `legacy-race-${suffix}`;
  const completionApplicationName = `pp-complete-${suffix}`;
  const legacyApplicationName = `pp-legacy-${suffix}`;
  const expiresAt = new Date(Date.now() + 365 * 24 * 60 * 60 * 1_000)
    .toISOString();
  let rolloutConfig: RolloutConfig | null = null;
  let purchasePrincipalId: string | null = null;
  let completionPromise: Promise<Settled> | null = null;
  let legacyPromise: Promise<Settled> | null = null;

  try {
    await insertUser(observer, sourceUserId, `Principal Source ${suffix}`);
    await insertUser(observer, targetUserId, `Principal Target ${suffix}`);
    const rolloutResult = await observer.queryObject<RolloutConfig>(`
      SELECT principal_mode, account_grant_mode
      FROM internal.purchase_identity_rollout_config
      WHERE config_key = 'current'
    `);
    rolloutConfig = rolloutResult.rows[0];
    await observer.queryArray(`
      UPDATE internal.purchase_identity_rollout_config
      SET principal_mode = 'stable',
          account_grant_mode = 'dual_read',
          updated_at = pg_catalog.CLOCK_TIMESTAMP()
      WHERE config_key = 'current'
    `);

    await observer.queryArray("SET ROLE service_role");
    const resolution = await observer.queryObject<{
      purchase_principal_id: string;
    }>(
      `
        SELECT result.purchase_principal_id::TEXT
        FROM public.begin_purchase_principal_resolution(
          $1::UUID,
          $2,
          1,
          1
        ) AS result
      `,
      [sourceUserId, capabilityHash],
    );
    purchasePrincipalId = resolution.rows[0]?.purchase_principal_id ?? null;
    assert(purchasePrincipalId != null);
    await observer.queryArray(
      `
        SELECT *
        FROM public.complete_purchase_principal_resolution(
          $1::UUID,
          $2::UUID,
          $3,
          1,
          $4::BIGINT,
          'pro',
          $5::TIMESTAMPTZ,
          FALSE,
          'free',
          NULL
        )
      `,
      [
        sourceUserId,
        purchasePrincipalId,
        capabilityHash,
        Date.now(),
        expiresAt,
      ],
    );
    const rebindResolution = await observer.queryObject<{
      purchase_principal_id: string;
    }>(
      `
        SELECT result.purchase_principal_id::TEXT
        FROM public.begin_purchase_principal_resolution(
          $1::UUID,
          $2,
          1,
          2
        ) AS result
      `,
      [targetUserId, capabilityHash],
    );
    assertEquals(
      rebindResolution.rows[0]?.purchase_principal_id,
      purchasePrincipalId,
      "same principal did not prepare target rebind",
    );
    await observer.queryArray("RESET ROLE");

    await setApplicationName(completionClient, completionApplicationName);
    await setApplicationName(legacyClient, legacyApplicationName);
    await beginTransaction(userBlocker);
    await userBlocker.queryArray(
      "SELECT id FROM public.users WHERE id = $1::UUID FOR UPDATE",
      [targetUserId],
    );
    const userBlockerPid = await backendPid(userBlocker);

    await beginTransaction(completionClient, true);
    const completionPid = await backendPid(completionClient);
    completionPromise = settle(
      completionClient.queryArray(
        `
          SELECT *
          FROM public.complete_purchase_principal_resolution(
            $1::UUID,
            $2::UUID,
            $3,
            2,
            $4::BIGINT,
            'pro',
            $5::TIMESTAMPTZ,
            FALSE,
            'free',
            NULL
          )
        `,
        [
          targetUserId,
          purchasePrincipalId,
          capabilityHash,
          Date.now(),
          expiresAt,
        ],
      ),
    );
    await waitUntilBlocked(
      observer,
      completionApplicationName,
      userBlockerPid,
    );

    await beginTransaction(legacyClient, true);
    legacyPromise = settle(
      legacyClient.queryArray(
        `
          SELECT *
          FROM public.apply_revenuecat_customer_state(
            $1,
            $2::BIGINT,
            'RENEWAL',
            $3,
            1,
            pg_catalog.JSONB_BUILD_ARRAY(
              pg_catalog.JSONB_BUILD_OBJECT(
                'subject_kind', 'customer',
                'candidate_user_ids',
                  pg_catalog.JSONB_BUILD_ARRAY($4::UUID),
                'authoritative_snapshot_at_ms', $2::BIGINT,
                'target_tier', 'pro',
                'target_expires_at', $5::TIMESTAMPTZ
              )
            )
          )
        `,
        [eventId, Date.now(), "b".repeat(64), targetUserId, expiresAt],
      ),
    );
    await waitUntilBlocked(observer, legacyApplicationName, completionPid);

    await userBlocker.queryArray("COMMIT");
    const completionResult = await completionPromise;
    assert(
      completionResult.ok,
      completionResult.ok ? undefined : describeError(completionResult.error),
    );
    await completionClient.queryArray("COMMIT");

    const legacyResult = await legacyPromise;
    assert(
      !legacyResult.ok,
      "legacy mutation unexpectedly won activation race",
    );
    assertStringIncludes(
      describeError(legacyResult.error),
      "revenuecat_legacy_identity_conflict",
    );
    await rollback(legacyClient);

    const finalState = await observer.queryObject<{
      principal_active: boolean;
      binding_exists: boolean;
      legacy_state_exists: boolean;
      legacy_queue_exists: boolean;
      rejected_event_exists: boolean;
    }>(
      `
        SELECT
          EXISTS (
            SELECT 1
            FROM internal.purchase_principals AS principal
            WHERE principal.id = $1::UUID
              AND principal.status = 'active'
          ) AS principal_active,
          EXISTS (
            SELECT 1
            FROM internal.purchase_principal_bindings AS binding
            WHERE binding.purchase_principal_id = $1::UUID
              AND binding.auth_user_id = $2::UUID
          ) AS binding_exists,
          EXISTS (
            SELECT 1
            FROM internal.legacy_revenuecat_entitlement_state AS legacy
            WHERE legacy.merian_user_id = $2::UUID
          ) AS legacy_state_exists,
          EXISTS (
            SELECT 1
            FROM internal.revenuecat_reconciliation_queue AS queue
            WHERE queue.merian_user_id = $2::UUID
          ) AS legacy_queue_exists,
          EXISTS (
            SELECT 1
            FROM internal.revenuecat_webhook_events AS event
            WHERE event.event_id = $3
          ) AS rejected_event_exists
      `,
      [purchasePrincipalId, targetUserId, eventId],
    );
    assertEquals(finalState.rows[0], {
      principal_active: true,
      binding_exists: true,
      legacy_state_exists: false,
      legacy_queue_exists: false,
      rejected_event_exists: false,
    });
  } finally {
    await rollback(userBlocker);
    if (completionPromise != null) await completionPromise;
    await rollback(completionClient);
    if (legacyPromise != null) await legacyPromise;
    await rollback(legacyClient);
    try {
      await observer.queryArray("RESET ROLE");
      if (rolloutConfig != null) {
        await observer.queryArray(
          `
            UPDATE internal.purchase_identity_rollout_config
            SET principal_mode = $1,
                account_grant_mode = $2,
                updated_at = pg_catalog.CLOCK_TIMESTAMP()
            WHERE config_key = 'current'
          `,
          [rolloutConfig.principal_mode, rolloutConfig.account_grant_mode],
        );
      }
      if (purchasePrincipalId != null) {
        await observer.queryArray(
          "DELETE FROM internal.purchase_principals WHERE id = $1::UUID",
          [purchasePrincipalId],
        );
      }
      for (const userId of [sourceUserId, targetUserId]) {
        await observer.queryArray(
          "DELETE FROM public.users WHERE id = $1::UUID",
          [userId],
        );
        await observer.queryArray(
          "DELETE FROM auth.users WHERE id = $1::UUID",
          [userId],
        );
      }
    } finally {
      await Promise.all(clients.map((client) => client.end().catch(() => {})));
    }
  }
});
