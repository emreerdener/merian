import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { insertUser } from "./exploreDbTestHelpers.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const CONFIGURED_DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL");
const DB_URL = CONFIGURED_DB_URL ?? DEFAULT_DB_URL;

type Settled<T> =
  | { ok: true; value: T }
  | { ok: false; error: unknown };

function settle<T>(promise: Promise<T>): Promise<Settled<T>> {
  return promise.then(
    (value) => ({ ok: true, value }),
    (error: unknown) => ({ ok: false, error }),
  );
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
        `[${label}] Could not connect to the configured disposable database: ${message}`,
        { cause: error },
      );
    }
    console.warn(
      `[${label}] Skipping DB integration test because the local disposable database is unavailable: ${message}`,
    );
    return null;
  }
}

async function hasAuthFirstPruner(
  client: Client,
  label: string,
): Promise<boolean> {
  const result = await client.queryObject<{ definition: string | null }>(`
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
      pg_catalog.TO_REGPROCEDURE(
        'public.prune_account_deletion_recovery_preparations(integer)'
      )
    ) AS definition
  `);
  const definition = result.rows[0]?.definition?.replace(/\s+/g, " ")
    .toLowerCase() ?? "";
  const authLock = definition.indexOf(
    "order by auth_user.id limit p_limit for update of auth_user skip locked",
  );
  const preparationLock = definition.indexOf(
    "from internal.account_deletion_recovery_preparations as preparation where preparation.user_id = candidate_user_id",
  );
  const installed = authLock >= 0 && preparationLock > authLock;

  if (!installed && CONFIGURED_DB_URL != null) {
    throw new Error(
      `[${label}] The configured database lacks Auth-first preparation pruning`,
    );
  }
  if (!installed) {
    console.warn(
      `[${label}] Skipping DB integration test because Auth-first preparation pruning is not installed locally`,
    );
  }
  return installed;
}

async function rollback(client: Client): Promise<void> {
  try {
    await client.queryArray("ROLLBACK");
  } catch {
    // Cleanup rollback is best-effort after a deliberately interrupted race.
  }
}

function proofHash(seed: string): string {
  return seed.replaceAll("-", "").repeat(2).slice(0, 64);
}

async function cleanupDeletionUser(
  client: Client,
  userId: string,
  proofHashes: string[],
): Promise<void> {
  await client.queryArray(
    `
      DELETE FROM internal.account_deletion_recovery_capabilities
      WHERE job_id IN (
        SELECT job.id
        FROM internal.account_deletion_jobs AS job
        WHERE job.user_id = $1::UUID
      )
    `,
    [userId],
  );
  await client.queryArray(
    "DELETE FROM internal.account_deletion_jobs WHERE user_id = $1::UUID",
    [userId],
  );
  for (const hash of proofHashes) {
    await client.queryArray(
      `
        DELETE FROM internal.account_deletion_expired_preparation_proofs
        WHERE proof_hash = $1
      `,
      [hash],
    );
  }
  await client.queryArray(
    `
      DELETE FROM internal.account_deletion_recovery_preparations
      WHERE user_id = $1::UUID
    `,
    [userId],
  );
  await client.queryArray(
    "DELETE FROM public.users WHERE id = $1::UUID",
    [userId],
  );
  await client.queryArray(
    "DELETE FROM auth.users WHERE id = $1::UUID",
    [userId],
  );
}

Deno.test("account deletion recovery DB - expiry pruning skips an active deletion and preserves its classification", async () => {
  const label = "accountDeletionRecoveryConcurrencyDb.pruner";
  const clients = await connectClients(label, 3);
  if (clients == null) return;

  const [observer, deletionClient, prunerClient] = clients;
  if (!(await hasAuthFirstPruner(observer, label))) {
    await Promise.all(clients.map((client) => client.end()));
    return;
  }

  const userId = crypto.randomUUID();
  const expiredRecoveryHash = proofHash(crypto.randomUUID());
  const expiredAcknowledgementHash = proofHash(crypto.randomUUID());
  const liveRecoveryHash = proofHash(crypto.randomUUID());
  const liveAcknowledgementHash = proofHash(crypto.randomUUID());
  const suffix = crypto.randomUUID().slice(0, 8);
  let prunerResult: Promise<Settled<number>> | null = null;

  try {
    await insertUser(observer, userId, `Deletion race ${suffix}`);
    await observer.queryArray(
      `
        INSERT INTO internal.account_deletion_recovery_preparations (
          user_id,
          recovery_secret_hash,
          acknowledgement_secret_hash,
          prepared_at,
          expires_at
        )
        VALUES
          (
            $1::UUID,
            $2,
            $3,
            pg_catalog.NOW() - INTERVAL '2 hours',
            pg_catalog.NOW() - INTERVAL '1 hour'
          ),
          (
            $1::UUID,
            $4,
            $5,
            pg_catalog.NOW(),
            pg_catalog.NOW() + INTERVAL '1 hour'
          )
      `,
      [
        userId,
        expiredRecoveryHash,
        expiredAcknowledgementHash,
        liveRecoveryHash,
        liveAcknowledgementHash,
      ],
    );

    await deletionClient.queryArray("BEGIN");
    await deletionClient.queryArray(
      "SELECT pg_catalog.SET_CONFIG('lock_timeout', '8s', TRUE)",
    );
    await deletionClient.queryArray(
      "SELECT id FROM auth.users WHERE id = $1::UUID FOR UPDATE",
      [userId],
    );
    prunerResult = settle(
      prunerClient.queryObject<{ retired_count: number }>(
        `
          SELECT public.prune_account_deletion_recovery_preparations(100)::INTEGER
            AS retired_count
        `,
      ).then((result) => result.rows[0].retired_count),
    );
    const settledPruner = await prunerResult;
    assert(
      settledPruner.ok,
      settledPruner.ok
        ? ""
        : `The Auth-first pruner failed while skipping active deletion: ${
          describeError(settledPruner.error)
        }`,
    );

    const preparationBeforeDeletion = await observer.queryObject<{
      preparation_count: number;
    }>(
      `
        SELECT pg_catalog.COUNT(*)::INTEGER AS preparation_count
        FROM internal.account_deletion_recovery_preparations AS preparation
        WHERE preparation.user_id = $1::UUID
      `,
      [userId],
    );
    assertEquals(preparationBeforeDeletion.rows[0].preparation_count, 2);

    await deletionClient.queryArray(
      "SELECT * FROM public.request_account_deletion($1::UUID)",
      [userId],
    );
    await deletionClient.queryArray("COMMIT");

    const state = await observer.queryObject<{
      committed_expired_proof: boolean;
      non_committed_expired_proof: boolean;
      live_capability: boolean;
      expired_capability: boolean;
      preparation_count: number;
    }>(
      `
        SELECT
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_expired_preparation_proofs
              AS proof
            WHERE proof.proof_hash = $2
              AND proof.proof_kind = 'recovery'
              AND proof.deletion_committed
          ) AS committed_expired_proof,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_expired_preparation_proofs
              AS proof
            WHERE proof.proof_hash = $2
              AND NOT proof.deletion_committed
          ) AS non_committed_expired_proof,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_capabilities AS capability
            INNER JOIN internal.account_deletion_jobs AS job
              ON job.id = capability.job_id
            WHERE job.user_id = $1::UUID
              AND capability.secret_hash = $3
          ) AS live_capability,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_capabilities AS capability
            INNER JOIN internal.account_deletion_jobs AS job
              ON job.id = capability.job_id
            WHERE job.user_id = $1::UUID
              AND capability.secret_hash = $2
          ) AS expired_capability,
          (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM internal.account_deletion_recovery_preparations
              AS preparation
            WHERE preparation.user_id = $1::UUID
          ) AS preparation_count
      `,
      [userId, expiredRecoveryHash, liveRecoveryHash],
    );

    assertEquals(state.rows[0], {
      committed_expired_proof: true,
      non_committed_expired_proof: false,
      live_capability: true,
      expired_capability: false,
      preparation_count: 0,
    });
  } finally {
    await rollback(deletionClient);
    if (prunerResult != null) await prunerResult;
    try {
      await observer.queryArray(
        `
          DELETE FROM internal.account_deletion_recovery_capabilities
          WHERE secret_hash IN ($1, $2)
             OR acknowledgement_secret_hash IN ($3, $4)
        `,
        [
          expiredRecoveryHash,
          liveRecoveryHash,
          expiredAcknowledgementHash,
          liveAcknowledgementHash,
        ],
      );
      await observer.queryArray(
        "DELETE FROM internal.account_deletion_jobs WHERE user_id = $1::UUID",
        [userId],
      );
      await observer.queryArray(
        `
          DELETE FROM internal.account_deletion_expired_preparation_proofs
          WHERE proof_hash IN ($1, $2, $3, $4)
        `,
        [
          expiredRecoveryHash,
          expiredAcknowledgementHash,
          liveRecoveryHash,
          liveAcknowledgementHash,
        ],
      );
      await observer.queryArray(
        "DELETE FROM internal.account_deletion_recovery_preparations WHERE user_id = $1::UUID",
        [userId],
      );
      await observer.queryArray(
        "DELETE FROM public.users WHERE id = $1::UUID",
        [userId],
      );
      await observer.queryArray(
        "DELETE FROM auth.users WHERE id = $1::UUID",
        [userId],
      );
    } finally {
      await Promise.all(clients.map((client) => client.end().catch(() => {})));
    }
  }
});

Deno.test("account deletion recovery DB - a pruned proof can never become a deletion capability", async () => {
  const label = "accountDeletionRecoveryConcurrencyDb.prunerFirst";
  const clients = await connectClients(label, 2);
  if (clients == null) return;

  const [observer, prunerClient] = clients;
  if (!(await hasAuthFirstPruner(observer, label))) {
    await Promise.all(clients.map((client) => client.end()));
    return;
  }

  const userId = crypto.randomUUID();
  const recoveryHash = proofHash(crypto.randomUUID());
  const acknowledgementHash = proofHash(crypto.randomUUID());
  const suffix = crypto.randomUUID().slice(0, 8);

  try {
    await insertUser(observer, userId, `Pruner first ${suffix}`);
    await observer.queryArray(
      `
        INSERT INTO internal.account_deletion_recovery_preparations (
          user_id,
          recovery_secret_hash,
          acknowledgement_secret_hash,
          prepared_at,
          expires_at
        )
        VALUES (
          $1::UUID,
          $2,
          $3,
          pg_catalog.NOW() - INTERVAL '2 hours',
          pg_catalog.NOW() - INTERVAL '1 hour'
        )
      `,
      [userId, recoveryHash, acknowledgementHash],
    );

    const pruneResult = await prunerClient.queryObject<{
      retired_count: number;
    }>(
      `
        SELECT public.prune_account_deletion_recovery_preparations(500)::INTEGER
          AS retired_count
      `,
    );
    assert(pruneResult.rows[0].retired_count >= 1);

    const prunedState = await observer.queryObject<{
      preparation_exists: boolean;
      recovery_tombstoned: boolean;
      acknowledgement_tombstoned: boolean;
    }>(
      `
        SELECT
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.user_id = $1::UUID
          ) AS preparation_exists,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_expired_preparation_proofs AS proof
            WHERE proof.proof_hash = $2
              AND proof.proof_kind = 'recovery'
              AND NOT proof.deletion_committed
          ) AS recovery_tombstoned,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_expired_preparation_proofs AS proof
            WHERE proof.proof_hash = $3
              AND proof.proof_kind = 'acknowledgement'
              AND NOT proof.deletion_committed
          ) AS acknowledgement_tombstoned
      `,
      [userId, recoveryHash, acknowledgementHash],
    );
    assertEquals(prunedState.rows[0], {
      preparation_exists: false,
      recovery_tombstoned: true,
      acknowledgement_tombstoned: true,
    });

    await observer.queryArray(
      "SELECT * FROM public.request_account_deletion($1::UUID)",
      [userId],
    );

    const committedState = await observer.queryObject<{
      expired_capability_exists: boolean;
      recovery_tombstone_committed: boolean;
      acknowledgement_tombstone_committed: boolean;
    }>(
      `
        SELECT
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_capabilities AS capability
            INNER JOIN internal.account_deletion_jobs AS job
              ON job.id = capability.job_id
            WHERE job.user_id = $1::UUID
              AND (
                capability.secret_hash = $2
                OR capability.acknowledgement_secret_hash = $3
              )
          ) AS expired_capability_exists,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_expired_preparation_proofs AS proof
            WHERE proof.proof_hash = $2
              AND proof.deletion_committed
          ) AS recovery_tombstone_committed,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_expired_preparation_proofs AS proof
            WHERE proof.proof_hash = $3
              AND proof.deletion_committed
          ) AS acknowledgement_tombstone_committed
      `,
      [userId, recoveryHash, acknowledgementHash],
    );
    assertEquals(committedState.rows[0], {
      expired_capability_exists: false,
      recovery_tombstone_committed: false,
      acknowledgement_tombstone_committed: false,
    });
  } finally {
    try {
      await cleanupDeletionUser(
        observer,
        userId,
        [recoveryHash, acknowledgementHash],
      );
    } finally {
      await Promise.all(clients.map((client) => client.end().catch(() => {})));
    }
  }
});

Deno.test("account deletion recovery DB - a one-row prune skips a locked account and remains bounded", async () => {
  const label = "accountDeletionRecoveryConcurrencyDb.boundedSkip";
  const clients = await connectClients(label, 3);
  if (clients == null) return;

  const [observer, blocker, prunerClient] = clients;
  if (!(await hasAuthFirstPruner(observer, label))) {
    await Promise.all(clients.map((client) => client.end()));
    return;
  }

  const uuidTail = crypto.randomUUID().replaceAll("-", "").slice(0, 10);
  const lockedUserId = `00000000-0000-4000-8000-${uuidTail}00`;
  const availableUserId = `00000000-0000-4000-8000-${uuidTail}01`;
  const lockedRecoveryHash = proofHash(crypto.randomUUID());
  const lockedAcknowledgementHash = proofHash(crypto.randomUUID());
  const availableRecoveryHash = proofHash(crypto.randomUUID());
  const availableAcknowledgementHash = proofHash(crypto.randomUUID());

  try {
    await insertUser(observer, lockedUserId, "Locked prune candidate");
    await insertUser(observer, availableUserId, "Available prune candidate");
    await observer.queryArray(
      `
        INSERT INTO internal.account_deletion_recovery_preparations (
          user_id,
          recovery_secret_hash,
          acknowledgement_secret_hash,
          prepared_at,
          expires_at
        )
        VALUES
          (
            $1::UUID,
            $3,
            $4,
            pg_catalog.NOW() - INTERVAL '2 hours',
            pg_catalog.NOW() - INTERVAL '1 hour'
          ),
          (
            $2::UUID,
            $5,
            $6,
            pg_catalog.NOW() - INTERVAL '2 hours',
            pg_catalog.NOW() - INTERVAL '1 hour'
          )
      `,
      [
        lockedUserId,
        availableUserId,
        lockedRecoveryHash,
        lockedAcknowledgementHash,
        availableRecoveryHash,
        availableAcknowledgementHash,
      ],
    );

    await blocker.queryArray("BEGIN");
    await blocker.queryArray(
      "SELECT id FROM auth.users WHERE id = $1::UUID FOR UPDATE",
      [lockedUserId],
    );

    const pruneResult = await prunerClient.queryObject<{
      retired_count: number;
    }>(
      `
        SELECT public.prune_account_deletion_recovery_preparations(1)::INTEGER
          AS retired_count
      `,
    );
    assertEquals(pruneResult.rows[0].retired_count, 1);

    const preparationState = await observer.queryObject<{
      locked_exists: boolean;
      available_exists: boolean;
    }>(
      `
        SELECT
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.user_id = $1::UUID
          ) AS locked_exists,
          EXISTS (
            SELECT 1
            FROM internal.account_deletion_recovery_preparations AS preparation
            WHERE preparation.user_id = $2::UUID
          ) AS available_exists
      `,
      [lockedUserId, availableUserId],
    );
    assertEquals(preparationState.rows[0], {
      locked_exists: true,
      available_exists: false,
    });
  } finally {
    await rollback(blocker);
    try {
      await cleanupDeletionUser(
        observer,
        lockedUserId,
        [lockedRecoveryHash, lockedAcknowledgementHash],
      );
      await cleanupDeletionUser(
        observer,
        availableUserId,
        [availableRecoveryHash, availableAcknowledgementHash],
      );
    } finally {
      await Promise.all(clients.map((client) => client.end().catch(() => {})));
    }
  }
});

Deno.test("account deletion recovery DB preflight describes the Auth-first lock contract", async () => {
  const source = await Deno.readTextFile(
    new URL(
      "../../migrations/20260813190637_serialize_account_deletion_preparation_pruning.sql",
      import.meta.url,
    ),
  );
  assertStringIncludes(source, "ORDER BY auth_user.id");
  assertStringIncludes(source, "LIMIT p_limit");
  assertStringIncludes(source, "FOR UPDATE OF auth_user SKIP LOCKED");
});
