import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const CONFIGURED_DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL");
const DB_URL = CONFIGURED_DB_URL ?? DEFAULT_DB_URL;
const PROJECT_REF = "qlarqavoqhkuwzmevrmf";

interface RolloutConfig {
  principal_mode: string;
  account_grant_mode: string;
  minimum_client_protocol: number;
}

function describeError(error: unknown): string {
  return error instanceof Error
    ? `${error.name}: ${error.message}`
    : String(error);
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
        `[${label}] Could not connect to configured DB integration test database: ${message}`,
        { cause: error },
      );
    }
    console.warn(
      `[${label}] Skipping DB integration test because the disposable database is unavailable: ${message}`,
    );
    return null;
  }
}

async function hasRolloutControl(
  client: Client,
  label: string,
): Promise<boolean> {
  const result = await client.queryObject<{ installed: boolean }>(`
    SELECT
      pg_catalog.TO_REGPROCEDURE(
        'internal.apply_purchase_identity_rollout_operation(uuid,integer,text,text,text,text,text,text,text,text,text,text,integer,integer,uuid)'
      ) IS NOT NULL
      AND pg_catalog.TO_REGCLASS(
        'internal.purchase_identity_rollout_operations'
      ) IS NOT NULL AS installed
  `);
  const installed = result.rows[0]?.installed === true;
  if (!installed && CONFIGURED_DB_URL != null) {
    throw new Error(
      `[${label}] The configured database lacks the purchase identity rollout control`,
    );
  }
  if (!installed) {
    console.warn(
      `[${label}] Skipping DB integration test because the rollout control is absent`,
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
          FROM pg_catalog.PG_STAT_ACTIVITY AS activity
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

async function rollback(client: Client): Promise<void> {
  try {
    await client.queryArray("ROLLBACK");
  } catch {
    // Best-effort cleanup after the deliberately contested transaction.
  }
}

Deno.test("purchase identity rollout DB - simultaneous exact operations serialize to one receipt", async () => {
  const label = "purchaseIdentityRolloutControlConcurrencyDb.exactReplay";
  const clients = await connectClients(label, 3);
  if (clients == null) return;

  const [observer, first, second] = clients;
  if (!(await hasRolloutControl(observer, label))) {
    await Promise.all(clients.map((client) => client.end()));
    return;
  }

  const operationId = crypto.randomUUID();
  const secondApplicationName = `purchase-rollout-replay-${operationId}`;
  let originalConfig: RolloutConfig | null = null;
  let firstCommitted = false;
  let secondCommitted = false;

  try {
    const config = await observer.queryObject<RolloutConfig>(`
      SELECT
        config.principal_mode,
        config.account_grant_mode,
        config.minimum_client_protocol
      FROM internal.purchase_identity_rollout_config AS config
      WHERE config.config_key = 'current'
    `);
    originalConfig = config.rows[0];
    assert(originalConfig != null);
    await observer.queryArray(`
      UPDATE internal.purchase_identity_rollout_config AS config
      SET principal_mode = 'legacy',
          account_grant_mode = 'dual_read',
          minimum_client_protocol = 1,
          updated_at = pg_catalog.CLOCK_TIMESTAMP()
      WHERE config.config_key = 'current'
    `);
    const databaseIdentity = await observer.queryObject<{
      system_identifier: string;
    }>(`
      SELECT control.system_identifier::TEXT AS system_identifier
      FROM pg_catalog.PG_CONTROL_SYSTEM() AS control
    `);
    const systemIdentifier = databaseIdentity.rows[0]?.system_identifier;
    assert(systemIdentifier != null);

    await first.queryArray("BEGIN");
    await first.queryArray(
      "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
    );
    const firstPid = await backendPid(first);
    const firstReceipt = await first.queryObject<{ already_applied: boolean }>(
      rolloutOperationSQL(),
      [operationId, systemIdentifier],
    );
    assertEquals(firstReceipt.rows[0]?.already_applied, false);

    await setApplicationName(second, secondApplicationName);
    await second.queryArray("BEGIN");
    await second.queryArray(
      "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
    );
    const secondReceiptPromise = second.queryObject<{
      already_applied: boolean;
    }>(rolloutOperationSQL(), [operationId, systemIdentifier]);
    await waitUntilBlocked(observer, secondApplicationName, firstPid);

    await first.queryArray("COMMIT");
    firstCommitted = true;
    const secondReceipt = await secondReceiptPromise;
    assertEquals(secondReceipt.rows[0]?.already_applied, true);
    await second.queryArray("COMMIT");
    secondCommitted = true;

    const finalState = await observer.queryObject<
      RolloutConfig & { operation_count: number }
    >(
      `
        SELECT
          config.principal_mode,
          config.account_grant_mode,
          config.minimum_client_protocol,
          (
            SELECT COUNT(*)::INTEGER
            FROM internal.purchase_identity_rollout_operations AS operation
            WHERE operation.id = $1::UUID
          ) AS operation_count
        FROM internal.purchase_identity_rollout_config AS config
        WHERE config.config_key = 'current'
      `,
      [operationId],
    );
    assertEquals(finalState.rows[0], {
      principal_mode: "stable",
      account_grant_mode: "dual_read",
      minimum_client_protocol: 3,
      operation_count: 1,
    });
  } finally {
    if (!firstCommitted) await rollback(first);
    if (!secondCommitted) await rollback(second);
    try {
      await observer.queryArray(
        `
          DELETE FROM internal.purchase_identity_rollout_operations
          WHERE id = $1::UUID
        `,
        [operationId],
      );
      if (originalConfig != null) {
        await observer.queryArray(
          `
            UPDATE internal.purchase_identity_rollout_config AS config
            SET principal_mode = $1,
                account_grant_mode = $2,
                minimum_client_protocol = $3,
                updated_at = pg_catalog.CLOCK_TIMESTAMP()
            WHERE config.config_key = 'current'
          `,
          [
            originalConfig.principal_mode,
            originalConfig.account_grant_mode,
            originalConfig.minimum_client_protocol,
          ],
        );
      }
    } finally {
      await Promise.all(clients.map((client) => client.end().catch(() => {})));
    }
  }
});

function rolloutOperationSQL(): string {
  return `
    SELECT receipt.already_applied
    FROM internal.apply_purchase_identity_rollout_operation(
      $1::UUID,
      1,
      'production',
      '${PROJECT_REF}',
      $2,
      'enable_stable',
      '${"1".repeat(40)}',
      '${"2".repeat(64)}',
      '${"3".repeat(64)}',
      '${"4".repeat(64)}',
      'legacy',
      'dual_read',
      1,
      3,
      NULL
    ) AS receipt
  `;
}
