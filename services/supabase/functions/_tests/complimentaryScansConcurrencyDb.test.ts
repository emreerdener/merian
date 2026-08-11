import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { insertUser } from "./exploreDbTestHelpers.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const CONFIGURED_DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL");
const DB_URL = CONFIGURED_DB_URL ?? DEFAULT_DB_URL;

interface RolloutState {
  entitlement_mode: string;
  required_client_protocol: number;
}

interface ReservationState {
  effective_plan: string;
  complimentary_client_scan_id: string | null;
  flash_fallback_used: boolean;
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

async function hasComplimentaryMigration(
  client: Client,
  label: string,
): Promise<boolean> {
  const result = await client.queryObject<{ installed: boolean }>(`
    SELECT
      pg_catalog.TO_REGCLASS('internal.complimentary_scan_usage') IS NOT NULL
      AND pg_catalog.TO_REGPROCEDURE(
        'public.reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)'
      ) IS NOT NULL AS installed
  `);
  const installed = result.rows[0]?.installed === true;
  if (!installed && CONFIGURED_DB_URL != null) {
    throw new Error(
      `[${label}] The configured database lacks the complimentary-scan migration`,
    );
  }
  if (!installed) {
    console.warn(
      `[${label}] Skipping DB integration test because the complimentary-scan migration is absent`,
    );
  }
  return installed;
}

async function setApplicationName(
  client: Client,
  value: string,
): Promise<void> {
  await client.queryArray(
    "SELECT pg_catalog.SET_CONFIG('application_name', $1, FALSE)",
    [value],
  );
}

async function grantCurrentAIConsent(
  client: Client,
  userId: string,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.user_adult_eligibility_receipts (
        id,
        user_id,
        policy_version,
        confirmed_at,
        confirmation_method,
        confirmation_text,
        platform,
        app_version,
        app_build
      )
      VALUES (
        $1::UUID,
        $2::UUID,
        '2026-08-03',
        pg_catalog.NOW(),
        'self_attestation',
        'I confirm I am 18 or older',
        'ios',
        'test',
        'ci'
      )
    `,
    [crypto.randomUUID(), userId],
  );

  await client.queryArray(
    `
      INSERT INTO public.user_terms_acceptance_receipts (
        id,
        user_id,
        terms_version,
        accepted_at,
        acceptance_text,
        platform,
        app_version,
        app_build
      )
      VALUES (
        $1::UUID,
        $2::UUID,
        '2026-08-03',
        pg_catalog.NOW(),
        'I accept the terms and allow this data sharing',
        'ios',
        'test',
        'ci'
      )
    `,
    [crypto.randomUUID(), userId],
  );

  await client.queryArray(
    `
      INSERT INTO public.user_ai_consent_events (
        id,
        user_id,
        provider,
        disclosure_version,
        event_kind,
        occurred_at,
        disclosure_text,
        action_text,
        platform,
        app_version,
        app_build
      )
      VALUES (
        $1::UUID,
        $2::UUID,
        'google_gemini',
        '2026-08-03.1',
        'granted',
        pg_catalog.NOW(),
        'Naturebook sends your scan data to Google Gemini, a third-party AI service, for identification.',
        'I accept the terms and allow this data sharing',
        'ios',
        'test',
        'ci'
      )
    `,
    [crypto.randomUUID(), userId],
  );
}

async function waitUntilAllCallersBlocked(
  observer: Client,
  applicationNames: string[],
): Promise<void> {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const result = await observer.queryObject<{ waiter_count: number }>(
      `
        SELECT pg_catalog.COUNT(*)::INTEGER AS waiter_count
        FROM pg_catalog.pg_stat_activity AS activity
        WHERE activity.application_name = ANY($1::TEXT[])
          AND activity.wait_event_type = 'Lock'
      `,
      [applicationNames],
    );
    if (result.rows[0]?.waiter_count === applicationNames.length) return;
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
  throw new Error("expected three overlapping lock waiters");
}

async function reserveScan(
  client: Client,
  userId: string,
  requestId: string,
  scanId: string,
): Promise<ReservationState> {
  const result = await client.queryObject<ReservationState>(
    `
      SELECT
        reservation.effective_plan,
        reservation.complimentary_client_scan_id::TEXT,
        reservation.flash_fallback_used
      FROM public.reserve_ai_quota(
        $1::UUID,
        'scan_identification',
        $2::UUID,
        pg_catalog.REPEAT('c', 64),
        $3::UUID,
        TRUE,
        2,
        FALSE
      ) AS reservation
    `,
    [userId, requestId, scanId],
  );
  assertEquals(result.rows.length, 1);
  return result.rows[0];
}

Deno.test("Complimentary scans concurrency DB - three overlapping holds serialize and the fourth falls back", async () => {
  const label = "complimentaryScansConcurrencyDb";
  const clients = await connectClients(label, 4);
  if (clients == null) return;

  const [observer, ...callers] = clients;
  let blockerTransactionOpen = false;
  let rolloutTouched = false;
  let callPromises: Promise<ReservationState>[] = [];
  const suffix = crypto.randomUUID().slice(0, 8);
  const userId = crypto.randomUUID();
  const scanIds = [
    crypto.randomUUID(),
    crypto.randomUUID(),
    crypto.randomUUID(),
  ];
  const applicationNames = callers.map((_, index) =>
    `complimentary-hold-${suffix}-${index + 1}`
  );
  let originalRollout: RolloutState | null = null;

  try {
    if (!(await hasComplimentaryMigration(observer, label))) return;

    await insertUser(observer, userId, `Complimentary Concurrency ${suffix}`);
    await grantCurrentAIConsent(observer, userId);
    const rollout = await observer.queryObject<RolloutState>(`
      SELECT
        config.entitlement_mode,
        config.required_client_protocol
      FROM internal.entitlement_rollout_config AS config
      WHERE config.config_key = 'current'
    `);
    originalRollout = rollout.rows[0];
    await observer.queryArray(`
      UPDATE internal.entitlement_rollout_config
      SET entitlement_mode = 'complimentary',
          required_client_protocol = 2
      WHERE config_key = 'current'
    `);
    rolloutTouched = true;

    await Promise.all(
      callers.map(async (client, index) => {
        await setApplicationName(client, applicationNames[index]);
        await client.queryArray(
          "SELECT pg_catalog.SET_CONFIG('lock_timeout', '10s', FALSE)",
        );
      }),
    );

    await observer.queryArray("BEGIN");
    blockerTransactionOpen = true;
    await observer.queryArray(
      "SELECT id FROM public.users WHERE id = $1::UUID FOR UPDATE",
      [userId],
    );

    callPromises = callers.map((client, index) =>
      reserveScan(
        client,
        userId,
        crypto.randomUUID(),
        scanIds[index],
      )
    );

    await waitUntilAllCallersBlocked(observer, applicationNames);
    await observer.queryArray("COMMIT");
    blockerTransactionOpen = false;

    const reservations = await Promise.all(callPromises);
    assertEquals(
      reservations.map((reservation) => reservation.effective_plan).sort(),
      ["pro_complimentary", "pro_complimentary", "pro_complimentary"],
    );
    assertEquals(
      reservations.map((reservation) =>
        reservation.complimentary_client_scan_id
      ).sort(),
      [...scanIds].sort(),
    );
    assert(
      reservations.every((reservation) => !reservation.flash_fallback_used),
    );

    const derived = await observer.queryObject<{
      held_count: number;
      total_count: number;
      scans_remaining: number;
      scans_available_to_start: number;
      in_flight_count: number;
    }>(
      `
        SELECT
          (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = $1::UUID
              AND usage.state = 'held'
          ) AS held_count,
          (
            SELECT pg_catalog.COUNT(*)::INTEGER
            FROM internal.complimentary_scan_usage AS usage
            WHERE usage.user_id = $1::UUID
          ) AS total_count,
          entitlement.scans_remaining,
          entitlement.scans_available_to_start,
          entitlement.in_flight_count
        FROM internal.resolve_effective_entitlement($1::UUID) AS entitlement
      `,
      [userId],
    );
    assertEquals(
      derived.rows[0],
      {
        held_count: 3,
        total_count: 3,
        scans_remaining: 3,
        scans_available_to_start: 0,
        in_flight_count: 3,
      },
      "three concurrent holds did not leave the expected derived balance",
    );

    const fourth = await reserveScan(
      observer,
      userId,
      crypto.randomUUID(),
      crypto.randomUUID(),
    );
    assertEquals(
      fourth,
      {
        effective_plan: "free",
        complimentary_client_scan_id: null,
        flash_fallback_used: true,
      },
      "fourth concurrent-test scan did not use Flash fallback",
    );
  } finally {
    if (blockerTransactionOpen) {
      await observer.queryArray("ROLLBACK").catch(() => {});
      blockerTransactionOpen = false;
    }
    await Promise.allSettled(callPromises);
    if (rolloutTouched && originalRollout != null) {
      await observer.queryArray(
        `
          UPDATE internal.entitlement_rollout_config
          SET entitlement_mode = $1,
              required_client_protocol = $2
          WHERE config_key = 'current'
        `,
        [
          originalRollout.entitlement_mode,
          originalRollout.required_client_protocol,
        ],
      ).catch(() => {});
    }
    await observer.queryArray(
      "DELETE FROM public.users WHERE id = $1::UUID",
      [userId],
    ).catch(() => {});
    await observer.queryArray(
      "DELETE FROM auth.users WHERE id = $1::UUID",
      [userId],
    ).catch(() => {});
    await Promise.all(clients.map((client) => client.end().catch(() => {})));
  }
});
