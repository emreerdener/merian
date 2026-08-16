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
  minimum_client_protocol: number;
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
    // Best-effort cleanup after an intentionally rejected resolver call.
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

async function backendPid(client: Client): Promise<number> {
  const result = await client.queryObject<{ pid: number }>(
    "SELECT pg_catalog.PG_BACKEND_PID() AS pid",
  );
  return result.rows[0].pid;
}

async function createStablePrincipal(
  client: Client,
  sourceUserId: string,
  capabilityHash: string,
): Promise<string> {
  await client.queryArray("SET ROLE service_role");
  try {
    const resolution = await client.queryObject<{
      purchase_principal_id: string;
    }>(
      `
        SELECT result.purchase_principal_id::TEXT
        FROM public.begin_purchase_principal_resolution(
          $1::UUID,
          $2,
          3,
          1
        ) AS result
      `,
      [sourceUserId, capabilityHash],
    );
    const purchasePrincipalId = resolution.rows[0]?.purchase_principal_id ??
      null;
    assert(purchasePrincipalId != null);
    await client.queryArray(
      `
        SELECT *
        FROM public.complete_purchase_principal_resolution(
          $1::UUID,
          $2::UUID,
          $3,
          1,
          $4::BIGINT,
          'free',
          NULL,
          FALSE,
          'free',
          NULL
        )
      `,
      [sourceUserId, purchasePrincipalId, capabilityHash, Date.now()],
    );
    return purchasePrincipalId;
  } finally {
    await client.queryArray("RESET ROLE");
  }
}

async function prepareRotation(
  client: Client,
  sourceUserId: string,
  capabilityHash: string,
  rotationId: string,
  secretHash: string,
): Promise<void> {
  await client.queryArray("SET ROLE service_role");
  try {
    await client.queryArray(
      `
        SELECT *
        FROM public.prepare_purchase_principal_signout_rotation(
          $1::UUID,
          $2,
          $3::UUID,
          $4,
          1,
          3
        )
      `,
      [sourceUserId, capabilityHash, rotationId, secretHash],
    );
  } finally {
    await client.queryArray("RESET ROLE");
  }
}

async function insertFreshAnonymousUser(
  client: Client,
  userId: string,
  publicName: string,
  rotationId: string,
): Promise<void> {
  await insertUser(client, userId, publicName);
  await client.queryArray(
    `
      UPDATE auth.users AS auth_user
      SET is_anonymous = TRUE,
          raw_app_meta_data =
            '{"provider":"anonymous","providers":[]}'::JSONB,
          created_at = rotation.created_at + INTERVAL '1 second',
          updated_at = rotation.created_at + INTERVAL '1 second'
      FROM internal.purchase_principal_signout_rotations AS rotation
      WHERE auth_user.id = $1::UUID
        AND rotation.id = $2::UUID
    `,
    [userId, rotationId],
  );
}

function executeRotationOperation(
  client: Client,
  operation: "claim" | "cancel",
  sourceUserId: string,
  destinationUserId: string,
  capabilityHash: string,
  rotationId: string,
  secretHash: string,
): Promise<unknown> {
  const authUserId = operation === "claim" ? destinationUserId : sourceUserId;
  const routine = operation === "claim"
    ? "claim_purchase_principal_signout_rotation"
    : "cancel_purchase_principal_signout_rotation";
  return client.queryArray(
    `
      SELECT *
      FROM public.${routine}(
        $1::UUID,
        $2,
        $3::UUID,
        $4,
        3
      )
    `,
    [authUserId, capabilityHash, rotationId, secretHash],
  );
}

Deno.test("purchase-principal sign-out rotation DB - prepared source defeats permanent resolver", async () => {
  const label = "purchasePrincipalSignoutRotationConcurrencyDb.resolver";
  const clients = await connectClients(label, 3);
  if (clients == null) return;

  const [observer, preparationClient, resolverClient] = clients;
  const installed = await observer.queryObject<{ installed: boolean }>(`
    SELECT pg_catalog.TO_REGPROCEDURE(
      'public.prepare_purchase_principal_signout_rotation(uuid,text,uuid,text,bigint,integer)'
    ) IS NOT NULL AS installed
  `);
  if (installed.rows[0]?.installed !== true) {
    await Promise.all(clients.map((client) => client.end()));
    if (CONFIGURED_DB_URL != null) {
      throw new Error(
        `[${label}] Configured database lacks sign-out rotations`,
      );
    }
    console.warn(`[${label}] Skipping because sign-out rotations are absent`);
    return;
  }

  const suffix = crypto.randomUUID().replaceAll("-", "").slice(0, 8);
  const sourceUserId = crypto.randomUUID();
  const permanentUserId = crypto.randomUUID();
  const rotationId = crypto.randomUUID();
  const capabilityHash = "a".repeat(56) + suffix;
  const secretHash = "b".repeat(56) + suffix;
  const resolverApplicationName = `pp-rotation-resolver-${suffix}`;
  let rolloutConfig: RolloutConfig | null = null;
  let purchasePrincipalId: string | null = null;
  let resolverPromise: Promise<Settled> | null = null;

  try {
    await insertUser(observer, sourceUserId, `Rotation Source ${suffix}`);
    await insertUser(
      observer,
      permanentUserId,
      `Rotation Permanent ${suffix}`,
    );
    const rollout = await observer.queryObject<RolloutConfig>(`
      SELECT principal_mode, account_grant_mode, minimum_client_protocol
      FROM internal.purchase_identity_rollout_config
      WHERE config_key = 'current'
    `);
    rolloutConfig = rollout.rows[0];
    await observer.queryArray(`
      UPDATE internal.purchase_identity_rollout_config
      SET principal_mode = 'stable',
          account_grant_mode = 'dual_read',
          minimum_client_protocol = 3,
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
          3,
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
          'free',
          NULL,
          FALSE,
          'free',
          NULL
        )
      `,
      [sourceUserId, purchasePrincipalId, capabilityHash, Date.now()],
    );
    await observer.queryArray("RESET ROLE");

    await preparationClient.queryArray("BEGIN");
    await preparationClient.queryArray(
      "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
    );
    await preparationClient.queryArray("SET LOCAL ROLE service_role");
    await preparationClient.queryArray(
      `
        SELECT *
        FROM public.prepare_purchase_principal_signout_rotation(
          $1::UUID,
          $2,
          $3::UUID,
          $4,
          1,
          3
        )
      `,
      [sourceUserId, capabilityHash, rotationId, secretHash],
    );
    const preparationPid = await backendPid(preparationClient);

    await resolverClient.queryArray(
      "SELECT pg_catalog.SET_CONFIG('application_name', $1, FALSE)",
      [resolverApplicationName],
    );
    await resolverClient.queryArray("BEGIN");
    await resolverClient.queryArray(
      "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
    );
    await resolverClient.queryArray("SET LOCAL ROLE service_role");
    resolverPromise = settle(
      resolverClient.queryArray(
        `
          SELECT *
          FROM public.begin_purchase_principal_resolution(
            $1::UUID,
            $2,
            3,
            2
          )
        `,
        [permanentUserId, capabilityHash],
      ),
    );
    await waitUntilBlocked(
      observer,
      resolverApplicationName,
      preparationPid,
    );

    await preparationClient.queryArray("COMMIT");
    const resolverResult = await resolverPromise;
    assert(
      !resolverResult.ok,
      "unrelated permanent resolver survived a committed sign-out rotation",
    );
    assertStringIncludes(
      describeError(resolverResult.error),
      "purchase_principal_signout_rotation_required",
    );
    await rollback(resolverClient);

    const finalState = await observer.queryObject<{
      bound_user_id: string;
      rotation_status: string;
    }>(
      `
        SELECT
          binding.auth_user_id::TEXT AS bound_user_id,
          rotation.status AS rotation_status
        FROM internal.purchase_principal_bindings AS binding
        JOIN internal.purchase_principal_signout_rotations AS rotation
          ON rotation.purchase_principal_id = binding.purchase_principal_id
        WHERE binding.purchase_principal_id = $1::UUID
          AND rotation.id = $2::UUID
      `,
      [purchasePrincipalId, rotationId],
    );
    assertEquals(finalState.rows[0], {
      bound_user_id: sourceUserId,
      rotation_status: "prepared",
    });
  } finally {
    await rollback(preparationClient);
    if (resolverPromise != null) await resolverPromise;
    await rollback(resolverClient);
    try {
      await observer.queryArray("RESET ROLE");
      if (rolloutConfig != null) {
        await observer.queryArray(
          `
            UPDATE internal.purchase_identity_rollout_config
            SET principal_mode = $1,
                account_grant_mode = $2,
                minimum_client_protocol = $3,
                updated_at = pg_catalog.CLOCK_TIMESTAMP()
            WHERE config_key = 'current'
          `,
          [
            rolloutConfig.principal_mode,
            rolloutConfig.account_grant_mode,
            rolloutConfig.minimum_client_protocol,
          ],
        );
      }
      await observer.queryArray(
        "DELETE FROM internal.purchase_principal_signout_rotations WHERE id = $1::UUID",
        [rotationId],
      );
      if (purchasePrincipalId != null) {
        await observer.queryArray(
          "DELETE FROM internal.purchase_principals WHERE id = $1::UUID",
          [purchasePrincipalId],
        );
      }
      for (const userId of [sourceUserId, permanentUserId]) {
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

Deno.test("purchase-principal sign-out rotation DB - claim and source cancellation have one terminal winner", async () => {
  const label = "purchasePrincipalSignoutRotationConcurrencyDb.claimCancel";
  const clients = await connectClients(label, 3);
  if (clients == null) return;

  const [observer, firstClient, secondClient] = clients;
  const installed = await observer.queryObject<{ installed: boolean }>(`
    SELECT pg_catalog.TO_REGPROCEDURE(
      'public.claim_purchase_principal_signout_rotation(uuid,text,uuid,text,integer)'
    ) IS NOT NULL AS installed
  `);
  if (installed.rows[0]?.installed !== true) {
    await Promise.all(clients.map((client) => client.end()));
    if (CONFIGURED_DB_URL != null) {
      throw new Error(
        `[${label}] Configured database lacks sign-out rotations`,
      );
    }
    console.warn(`[${label}] Skipping because sign-out rotations are absent`);
    return;
  }

  const rollout = await observer.queryObject<RolloutConfig>(`
    SELECT principal_mode, account_grant_mode, minimum_client_protocol
    FROM internal.purchase_identity_rollout_config
    WHERE config_key = 'current'
  `);
  const rolloutConfig = rollout.rows[0];
  const purchasePrincipalIds: string[] = [];
  const rotationIds: string[] = [];
  const userIds: string[] = [];
  let pendingLoser: Promise<Settled> | null = null;

  try {
    await observer.queryArray(`
      UPDATE internal.purchase_identity_rollout_config
      SET principal_mode = 'stable',
          account_grant_mode = 'dual_read',
          minimum_client_protocol = 3,
          updated_at = pg_catalog.CLOCK_TIMESTAMP()
      WHERE config_key = 'current'
    `);

    for (const winningOperation of ["claim", "cancel"] as const) {
      const suffix = crypto.randomUUID().replaceAll("-", "").slice(0, 8);
      const sourceUserId = crypto.randomUUID();
      const destinationUserId = crypto.randomUUID();
      const rotationId = crypto.randomUUID();
      const capabilityHash = "c".repeat(56) + suffix;
      const secretHash = "d".repeat(56) + suffix;
      const losingOperation = winningOperation === "claim" ? "cancel" : "claim";
      const applicationName = `pp-rotation-${losingOperation}-${suffix}`;
      userIds.push(sourceUserId, destinationUserId);
      rotationIds.push(rotationId);

      await insertUser(observer, sourceUserId, `Rotation Source ${suffix}`);
      const purchasePrincipalId = await createStablePrincipal(
        observer,
        sourceUserId,
        capabilityHash,
      );
      purchasePrincipalIds.push(purchasePrincipalId);
      await prepareRotation(
        observer,
        sourceUserId,
        capabilityHash,
        rotationId,
        secretHash,
      );
      await insertFreshAnonymousUser(
        observer,
        destinationUserId,
        `Rotation Destination ${suffix}`,
        rotationId,
      );

      await firstClient.queryArray("BEGIN");
      await firstClient.queryArray(
        "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
      );
      await firstClient.queryArray("SET LOCAL ROLE service_role");
      await executeRotationOperation(
        firstClient,
        winningOperation,
        sourceUserId,
        destinationUserId,
        capabilityHash,
        rotationId,
        secretHash,
      );
      const winnerPid = await backendPid(firstClient);

      await secondClient.queryArray(
        "SELECT pg_catalog.SET_CONFIG('application_name', $1, FALSE)",
        [applicationName],
      );
      await secondClient.queryArray("BEGIN");
      await secondClient.queryArray(
        "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
      );
      await secondClient.queryArray("SET LOCAL ROLE service_role");
      pendingLoser = settle(
        executeRotationOperation(
          secondClient,
          losingOperation,
          sourceUserId,
          destinationUserId,
          capabilityHash,
          rotationId,
          secretHash,
        ),
      );
      await waitUntilBlocked(observer, applicationName, winnerPid);

      await firstClient.queryArray("COMMIT");
      const loserResult = await pendingLoser;
      pendingLoser = null;
      assert(
        !loserResult.ok,
        `${losingOperation} survived a committed ${winningOperation}`,
      );
      assertStringIncludes(
        describeError(loserResult.error),
        "purchase_principal_signout_rotation_terminal_conflict",
      );
      await rollback(secondClient);

      const finalState = await observer.queryObject<{
        bound_user_id: string;
        rotation_status: string;
      }>(
        `
          SELECT
            binding.auth_user_id::TEXT AS bound_user_id,
            rotation.status AS rotation_status
          FROM internal.purchase_principal_bindings AS binding
          JOIN internal.purchase_principal_signout_rotations AS rotation
            ON rotation.purchase_principal_id = binding.purchase_principal_id
          WHERE binding.purchase_principal_id = $1::UUID
            AND rotation.id = $2::UUID
        `,
        [purchasePrincipalId, rotationId],
      );
      assertEquals(
        finalState.rows[0],
        winningOperation === "claim"
          ? {
            bound_user_id: destinationUserId,
            rotation_status: "completed",
          }
          : {
            bound_user_id: sourceUserId,
            rotation_status: "cancelled",
          },
      );
    }
  } finally {
    await rollback(firstClient);
    if (pendingLoser != null) await pendingLoser;
    await rollback(secondClient);
    try {
      await observer.queryArray("RESET ROLE");
      await observer.queryArray(
        `
          UPDATE internal.purchase_identity_rollout_config
          SET principal_mode = $1,
              account_grant_mode = $2,
              minimum_client_protocol = $3,
              updated_at = pg_catalog.CLOCK_TIMESTAMP()
          WHERE config_key = 'current'
        `,
        [
          rolloutConfig.principal_mode,
          rolloutConfig.account_grant_mode,
          rolloutConfig.minimum_client_protocol,
        ],
      );
      for (const rotationId of rotationIds) {
        await observer.queryArray(
          "DELETE FROM internal.purchase_principal_signout_rotations WHERE id = $1::UUID",
          [rotationId],
        );
      }
      for (const purchasePrincipalId of purchasePrincipalIds) {
        await observer.queryArray(
          "DELETE FROM internal.purchase_principals WHERE id = $1::UUID",
          [purchasePrincipalId],
        );
      }
      for (const userId of userIds) {
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

Deno.test("purchase-principal sign-out rotation DB - expiry is terminal before ordinary resolution resumes", async () => {
  const label = "purchasePrincipalSignoutRotationConcurrencyDb.expiry";
  const clients = await connectClients(label, 1);
  if (clients == null) return;

  const [client] = clients;
  const installed = await client.queryObject<{ installed: boolean }>(`
    SELECT pg_catalog.TO_REGPROCEDURE(
      'public.claim_purchase_principal_signout_rotation(uuid,text,uuid,text,integer)'
    ) IS NOT NULL AS installed
  `);
  if (installed.rows[0]?.installed !== true) {
    await client.end();
    if (CONFIGURED_DB_URL != null) {
      throw new Error(
        `[${label}] Configured database lacks sign-out rotations`,
      );
    }
    console.warn(`[${label}] Skipping because sign-out rotations are absent`);
    return;
  }

  const suffix = crypto.randomUUID().replaceAll("-", "").slice(0, 8);
  const sourceUserId = crypto.randomUUID();
  const destinationUserId = crypto.randomUUID();
  const permanentUserId = crypto.randomUUID();
  const rotationId = crypto.randomUUID();
  const capabilityHash = "e".repeat(56) + suffix;
  const secretHash = "f".repeat(56) + suffix;
  const rollout = await client.queryObject<RolloutConfig>(`
    SELECT principal_mode, account_grant_mode, minimum_client_protocol
    FROM internal.purchase_identity_rollout_config
    WHERE config_key = 'current'
  `);
  const rolloutConfig = rollout.rows[0];
  let purchasePrincipalId: string | null = null;

  try {
    await client.queryArray(`
      UPDATE internal.purchase_identity_rollout_config
      SET principal_mode = 'stable',
          account_grant_mode = 'dual_read',
          minimum_client_protocol = 3,
          updated_at = pg_catalog.CLOCK_TIMESTAMP()
      WHERE config_key = 'current'
    `);
    await insertUser(client, sourceUserId, `Rotation Source ${suffix}`);
    await insertUser(client, permanentUserId, `Rotation Permanent ${suffix}`);
    purchasePrincipalId = await createStablePrincipal(
      client,
      sourceUserId,
      capabilityHash,
    );
    await prepareRotation(
      client,
      sourceUserId,
      capabilityHash,
      rotationId,
      secretHash,
    );
    await insertFreshAnonymousUser(
      client,
      destinationUserId,
      `Rotation Destination ${suffix}`,
      rotationId,
    );
    await client.queryArray(
      `
        UPDATE internal.purchase_principal_signout_rotations
        SET created_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '2 days',
            expires_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '1 day',
            updated_at = pg_catalog.CLOCK_TIMESTAMP()
        WHERE id = $1::UUID
      `,
      [rotationId],
    );

    await client.queryArray("SET ROLE service_role");
    const health = await client.queryObject<{
      expired_prepared_count: number;
    }>(`
      SELECT result.expired_prepared_count::INTEGER
      FROM public.get_purchase_principal_signout_rotation_health() AS result
    `);
    assert(
      (health.rows[0]?.expired_prepared_count ?? 0) >= 1,
      "The health pass must report and terminalize the overdue preparation.",
    );

    const expired = await client.queryObject<{
      rotation_status: string;
      binding_generation: number | null;
    }>(
      `
        SELECT result.rotation_status, result.binding_generation
        FROM public.claim_purchase_principal_signout_rotation(
          $1::UUID,
          $2,
          $3::UUID,
          $4,
          3
        ) AS result
      `,
      [destinationUserId, capabilityHash, rotationId, secretHash],
    );
    assertEquals(expired.rows[0], {
      rotation_status: "expired",
      binding_generation: null,
    });

    const cancelledAfterHealth = await client.queryObject<{
      rotation_status: string;
      already_cancelled: boolean;
    }>(
      `
        SELECT result.rotation_status, result.already_cancelled
        FROM public.cancel_purchase_principal_signout_rotation(
          $1::UUID,
          $2,
          $3::UUID,
          $4,
          3
        ) AS result
      `,
      [sourceUserId, capabilityHash, rotationId, secretHash],
    );
    assertEquals(cancelledAfterHealth.rows[0], {
      rotation_status: "expired",
      already_cancelled: false,
    });

    const resumed = await client.queryObject<{
      resolution_mode: string;
      purchase_principal_id: string;
    }>(
      `
        SELECT
          result.resolution_mode,
          result.purchase_principal_id::TEXT
        FROM public.begin_purchase_principal_resolution(
          $1::UUID,
          $2,
          3,
          2
        ) AS result
      `,
      [permanentUserId, capabilityHash],
    );
    assertEquals(resumed.rows[0], {
      resolution_mode: "stable",
      purchase_principal_id: purchasePrincipalId,
    });
    await client.queryArray("RESET ROLE");

    const finalState = await client.queryObject<{
      bound_user_id: string;
      rotation_status: string;
    }>(
      `
        SELECT
          binding.auth_user_id::TEXT AS bound_user_id,
          rotation.status AS rotation_status
        FROM internal.purchase_principal_bindings AS binding
        JOIN internal.purchase_principal_signout_rotations AS rotation
          ON rotation.purchase_principal_id = binding.purchase_principal_id
        WHERE rotation.id = $1::UUID
      `,
      [rotationId],
    );
    assertEquals(finalState.rows[0], {
      bound_user_id: sourceUserId,
      rotation_status: "expired",
    });
  } finally {
    try {
      await client.queryArray("RESET ROLE");
      await client.queryArray(
        `
          UPDATE internal.purchase_identity_rollout_config
          SET principal_mode = $1,
              account_grant_mode = $2,
              minimum_client_protocol = $3,
              updated_at = pg_catalog.CLOCK_TIMESTAMP()
          WHERE config_key = 'current'
        `,
        [
          rolloutConfig.principal_mode,
          rolloutConfig.account_grant_mode,
          rolloutConfig.minimum_client_protocol,
        ],
      );
      await client.queryArray(
        "DELETE FROM internal.purchase_principal_signout_rotations WHERE id = $1::UUID",
        [rotationId],
      );
      if (purchasePrincipalId != null) {
        await client.queryArray(
          "DELETE FROM internal.purchase_principals WHERE id = $1::UUID",
          [purchasePrincipalId],
        );
      }
      for (
        const userId of [sourceUserId, destinationUserId, permanentUserId]
      ) {
        await client.queryArray(
          "DELETE FROM public.users WHERE id = $1::UUID",
          [userId],
        );
        await client.queryArray(
          "DELETE FROM auth.users WHERE id = $1::UUID",
          [userId],
        );
      }
    } finally {
      await client.end().catch(() => {});
    }
  }
});

Deno.test("purchase-principal sign-out rotation DB - resolver completion begun before prepare stays stale after every terminal outcome", async () => {
  const label = "purchasePrincipalSignoutRotationConcurrencyDb.intentFence";
  const clients = await connectClients(label, 1);
  if (clients == null) return;

  const [client] = clients;
  const installed = await client.queryObject<{ installed: boolean }>(`
    SELECT pg_catalog.TO_REGPROCEDURE(
      'public.prepare_purchase_principal_signout_rotation(uuid,text,uuid,text,bigint,integer)'
    ) IS NOT NULL AS installed
  `);
  if (installed.rows[0]?.installed !== true) {
    await client.end();
    if (CONFIGURED_DB_URL != null) {
      throw new Error(
        `[${label}] Configured database lacks sign-out rotations`,
      );
    }
    console.warn(`[${label}] Skipping because sign-out rotations are absent`);
    return;
  }

  const rollout = await client.queryObject<RolloutConfig>(`
    SELECT principal_mode, account_grant_mode, minimum_client_protocol
    FROM internal.purchase_identity_rollout_config
    WHERE config_key = 'current'
  `);
  const rolloutConfig = rollout.rows[0];
  const purchasePrincipalIds: string[] = [];
  const rotationIds: string[] = [];
  const userIds: string[] = [];

  try {
    await client.queryArray(`
      UPDATE internal.purchase_identity_rollout_config
      SET principal_mode = 'stable',
          account_grant_mode = 'dual_read',
          minimum_client_protocol = 3,
          updated_at = pg_catalog.CLOCK_TIMESTAMP()
      WHERE config_key = 'current'
    `);

    for (const terminalOperation of ["claim", "cancel", "expire"] as const) {
      const suffix = crypto.randomUUID().replaceAll("-", "").slice(0, 8);
      const sourceUserId = crypto.randomUUID();
      const destinationUserId = crypto.randomUUID();
      const permanentUserId = crypto.randomUUID();
      const rotationId = crypto.randomUUID();
      const capabilityHash = "7".repeat(56) + suffix;
      const secretHash = "8".repeat(56) + suffix;
      userIds.push(sourceUserId, destinationUserId, permanentUserId);
      rotationIds.push(rotationId);

      await insertUser(client, sourceUserId, `Fence Source ${suffix}`);
      await insertUser(client, permanentUserId, `Fence Permanent ${suffix}`);
      const purchasePrincipalId = await createStablePrincipal(
        client,
        sourceUserId,
        capabilityHash,
      );
      purchasePrincipalIds.push(purchasePrincipalId);

      // Phase one commits before preparation. Its phase-two token must remain
      // invalid after every way the rotation can become terminal.
      await client.queryArray("SET ROLE service_role");
      const delayedBegin = await client.queryObject<{
        purchase_principal_id: string;
        binding_intent_generation: bigint;
      }>(
        `
          SELECT
            result.purchase_principal_id::TEXT,
            result.binding_intent_generation
          FROM public.begin_purchase_principal_resolution(
            $1::UUID,
            $2,
            3,
            2
          ) AS result
        `,
        [permanentUserId, capabilityHash],
      );
      assertEquals(delayedBegin.rows[0], {
        purchase_principal_id: purchasePrincipalId,
        binding_intent_generation: 2n,
      });
      await client.queryArray("RESET ROLE");

      await prepareRotation(
        client,
        sourceUserId,
        capabilityHash,
        rotationId,
        secretHash,
      );
      if (terminalOperation !== "cancel") {
        await insertFreshAnonymousUser(
          client,
          destinationUserId,
          `Fence Destination ${suffix}`,
          rotationId,
        );
      }
      if (terminalOperation === "expire") {
        await client.queryArray(
          `
            UPDATE internal.purchase_principal_signout_rotations
            SET created_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '2 days',
                expires_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '1 day',
                updated_at = pg_catalog.CLOCK_TIMESTAMP()
            WHERE id = $1::UUID
          `,
          [rotationId],
        );
      }

      await client.queryArray("SET ROLE service_role");
      if (terminalOperation === "claim") {
        await executeRotationOperation(
          client,
          "claim",
          sourceUserId,
          destinationUserId,
          capabilityHash,
          rotationId,
          secretHash,
        );
      } else if (terminalOperation === "cancel") {
        await executeRotationOperation(
          client,
          "cancel",
          sourceUserId,
          destinationUserId,
          capabilityHash,
          rotationId,
          secretHash,
        );
      } else {
        const expired = await client.queryObject<{
          rotation_status: string;
        }>(
          `
            SELECT result.rotation_status
            FROM public.claim_purchase_principal_signout_rotation(
              $1::UUID,
              $2,
              $3::UUID,
              $4,
              3
            ) AS result
          `,
          [destinationUserId, capabilityHash, rotationId, secretHash],
        );
        assertEquals(expired.rows[0]?.rotation_status, "expired");
      }

      const delayedCompletion = await settle(
        client.queryArray(
          `
            SELECT *
            FROM public.complete_purchase_principal_resolution(
              $1::UUID,
              $2::UUID,
              $3,
              2,
              $4::BIGINT,
              'free',
              NULL,
              FALSE,
              'free',
              NULL
            )
          `,
          [
            permanentUserId,
            purchasePrincipalId,
            capabilityHash,
            Date.now(),
          ],
        ),
      );
      assert(
        !delayedCompletion.ok,
        "delayed resolver overwrote the terminal sign-out binding",
      );
      assertStringIncludes(
        describeError(delayedCompletion.error),
        "purchase_principal_binding_intent_stale",
      );
      await client.queryArray("RESET ROLE");

      const expectedBoundUserId = terminalOperation === "claim"
        ? destinationUserId
        : sourceUserId;
      const expectedStatus = terminalOperation === "claim"
        ? "completed"
        : terminalOperation === "cancel"
        ? "cancelled"
        : "expired";
      const fencedState = await client.queryObject<{
        bound_user_id: string;
        rotation_status: string;
      }>(
        `
          SELECT
            binding.auth_user_id::TEXT AS bound_user_id,
            rotation.status AS rotation_status
          FROM internal.purchase_principal_bindings AS binding
          JOIN internal.purchase_principal_signout_rotations AS rotation
            ON rotation.purchase_principal_id = binding.purchase_principal_id
          WHERE rotation.id = $1::UUID
        `,
        [rotationId],
      );
      assertEquals(fencedState.rows[0], {
        bound_user_id: expectedBoundUserId,
        rotation_status: expectedStatus,
      });

      // The fence invalidates only tokens issued before preparation. A later
      // resolver generation for the still-bound identity remains usable.
      await client.queryArray("SET ROLE service_role");
      const resumed = await client.queryObject<{
        purchase_principal_id: string;
        binding_intent_generation: bigint;
      }>(
        `
          SELECT
            result.purchase_principal_id::TEXT,
            result.binding_intent_generation
          FROM public.begin_purchase_principal_resolution(
            $1::UUID,
            $2,
            3,
            3
          ) AS result
        `,
        [expectedBoundUserId, capabilityHash],
      );
      assertEquals(resumed.rows[0], {
        purchase_principal_id: purchasePrincipalId,
        binding_intent_generation: 3n,
      });
      await client.queryArray(
        `
          SELECT *
          FROM public.complete_purchase_principal_resolution(
            $1::UUID,
            $2::UUID,
            $3,
            3,
            $4::BIGINT,
            'free',
            NULL,
            FALSE,
            'free',
            NULL
          )
        `,
        [
          expectedBoundUserId,
          purchasePrincipalId,
          capabilityHash,
          Date.now(),
        ],
      );
      await client.queryArray("RESET ROLE");
    }
  } finally {
    try {
      await client.queryArray("RESET ROLE");
      await client.queryArray(
        `
          UPDATE internal.purchase_identity_rollout_config
          SET principal_mode = $1,
              account_grant_mode = $2,
              minimum_client_protocol = $3,
              updated_at = pg_catalog.CLOCK_TIMESTAMP()
          WHERE config_key = 'current'
        `,
        [
          rolloutConfig.principal_mode,
          rolloutConfig.account_grant_mode,
          rolloutConfig.minimum_client_protocol,
        ],
      );
      for (const rotationId of rotationIds) {
        await client.queryArray(
          "DELETE FROM internal.purchase_principal_signout_rotations WHERE id = $1::UUID",
          [rotationId],
        );
      }
      for (const purchasePrincipalId of purchasePrincipalIds) {
        await client.queryArray(
          "DELETE FROM internal.purchase_principals WHERE id = $1::UUID",
          [purchasePrincipalId],
        );
      }
      for (const userId of userIds) {
        await client.queryArray(
          "DELETE FROM public.users WHERE id = $1::UUID",
          [userId],
        );
        await client.queryArray(
          "DELETE FROM auth.users WHERE id = $1::UUID",
          [userId],
        );
      }
    } finally {
      await client.end().catch(() => {});
    }
  }
});
