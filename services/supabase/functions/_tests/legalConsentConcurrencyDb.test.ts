import { assert, assertEquals } from "@std/assert";
import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import { insertUser } from "./exploreDbTestHelpers.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const CONFIGURED_DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL");
const DB_URL = CONFIGURED_DB_URL ?? DEFAULT_DB_URL;

type Provider = "ai" | "analytics";

interface AppendResult {
  accepted: boolean;
  event_revision: string | null;
  accepted_parent_id: string | null;
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

async function hasCausalConsentMigration(
  client: Client,
  label: string,
): Promise<boolean> {
  const result = await client.queryObject<{ installed: boolean }>(`
    SELECT
      pg_catalog.TO_REGPROCEDURE(
        'public.append_user_ai_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)'
      ) IS NOT NULL
      AND pg_catalog.TO_REGPROCEDURE(
        'public.append_user_analytics_consent_event(uuid,text,text,timestamptz,text,text,text,text,text,uuid)'
      ) IS NOT NULL AS installed
  `);
  const installed = result.rows[0]?.installed === true;
  if (!installed && CONFIGURED_DB_URL != null) {
    throw new Error(
      `[${label}] The configured database lacks the causal consent migration`,
    );
  }
  if (!installed) {
    console.warn(
      `[${label}] Skipping DB integration test because the causal consent migration is absent`,
    );
  }
  return installed;
}

async function configureAuthenticatedCaller(
  client: Client,
  userId: string,
  applicationName: string,
): Promise<void> {
  await client.queryArray(
    "SELECT pg_catalog.SET_CONFIG('application_name', $1, FALSE)",
    [applicationName],
  );
  await client.queryArray(
    "SELECT pg_catalog.SET_CONFIG('request.jwt.claims', $1, FALSE)",
    [JSON.stringify({ sub: userId, role: "authenticated" })],
  );
  await client.queryArray("SET ROLE authenticated");
  await client.queryArray(
    "SELECT pg_catalog.SET_CONFIG('lock_timeout', '10s', FALSE)",
  );
}

async function appendConsent(
  client: Client,
  provider: Provider,
  id: string,
  eventKind: "granted" | "revoked",
  parentId: string | null,
  occurredAt: string,
): Promise<AppendResult> {
  const action = eventKind === "granted"
    ? "The test device grants permission."
    : "The test device withdraws permission.";
  const query = provider === "ai"
    ? `
      SELECT
        result.accepted,
        result.event_revision::TEXT,
        result.accepted_parent_id::TEXT
      FROM public.append_user_ai_consent_event(
        $1::UUID,
        '2026-08-04.1',
        $2,
        $3::TIMESTAMPTZ,
        'Naturebook sends observation data to Google Gemini for AI-powered identification.',
        $4,
        'ios',
        'concurrency-test',
        'ci',
        $5::UUID
      ) AS result
    `
    : `
      SELECT
        result.accepted,
        result.event_revision::TEXT,
        result.accepted_parent_id::TEXT
      FROM public.append_user_analytics_consent_event(
        $1::UUID,
        '2026-08-04',
        $2,
        $3::TIMESTAMPTZ,
        'Share usage and diagnostics to help improve Naturebook.',
        $4,
        'ios',
        'concurrency-test',
        'ci',
        $5::UUID
      ) AS result
    `;
  const result = await client.queryObject<AppendResult>(query, [
    id,
    eventKind,
    occurredAt,
    action,
    parentId,
  ]);
  assertEquals(result.rows.length, 1);
  return result.rows[0];
}

async function waitUntilCallersAreBlocked(
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
  throw new Error("consent callers did not reach the account-row lock");
}

async function latestConsentEvent(
  observer: Client,
  provider: Provider,
  userId: string,
): Promise<{
  id: string;
  event_kind: string;
  consent_revision: string;
  causal_parent_id: string | null;
}> {
  const table = provider === "ai"
    ? "public.user_ai_consent_events"
    : "public.user_analytics_consent_events";
  const providerName = provider === "ai" ? "google_gemini" : "posthog";
  const result = await observer.queryObject<{
    id: string;
    event_kind: string;
    consent_revision: string;
    causal_parent_id: string | null;
  }>(
    `
    SELECT
      events.id::TEXT,
      events.event_kind,
      events.consent_revision::TEXT,
      events.causal_parent_id::TEXT
    FROM ${table} AS events
    WHERE events.user_id = $1::UUID
      AND events.provider = $2
    ORDER BY events.consent_revision DESC
    LIMIT 1
  `,
    [userId, providerName],
  );
  assertEquals(result.rows.length, 1);
  return result.rows[0];
}

async function proveDenyWinsRace(
  observer: Client,
  grantClient: Client,
  revokeClient: Client,
  provider: Provider,
  userId: string,
  applicationNames: string[],
  pendingCalls: Promise<AppendResult>[],
): Promise<void> {
  const baselineId = crypto.randomUUID();
  const delayedGrantId = crypto.randomUUID();
  const revocationId = crypto.randomUUID();
  const baseline = await appendConsent(
    grantClient,
    provider,
    baselineId,
    "granted",
    null,
    "2026-08-05T10:00:00Z",
  );
  assert(baseline.accepted);
  assert(baseline.event_revision != null);
  const baselineRevision = BigInt(baseline.event_revision);

  await observer.queryArray("BEGIN");
  await observer.queryArray(
    "SELECT id FROM public.users WHERE id = $1::UUID FOR UPDATE",
    [userId],
  );

  const delayedGrant = appendConsent(
    grantClient,
    provider,
    delayedGrantId,
    "granted",
    baselineId,
    "2026-08-05T12:00:00Z",
  );
  const revocation = appendConsent(
    revokeClient,
    provider,
    revocationId,
    "revoked",
    baselineId,
    "2026-08-05T11:00:00Z",
  );
  pendingCalls.push(delayedGrant, revocation);

  await waitUntilCallersAreBlocked(observer, applicationNames);
  await observer.queryArray("COMMIT");

  const [grantResult, revocationResult] = await Promise.all([
    delayedGrant,
    revocation,
  ]);
  pendingCalls.length = 0;

  assert(revocationResult.accepted);
  assert(revocationResult.event_revision != null);
  const revocationRevision = BigInt(revocationResult.event_revision);
  assert(revocationRevision > baselineRevision);
  assert(
    revocationResult.accepted_parent_id === baselineId ||
      revocationResult.accepted_parent_id === delayedGrantId,
  );
  if (grantResult.accepted) {
    assert(grantResult.event_revision != null);
    assert(revocationRevision > BigInt(grantResult.event_revision));
    assertEquals(revocationResult.accepted_parent_id, delayedGrantId);
  } else {
    assertEquals(revocationResult.accepted_parent_id, baselineId);
  }

  const latest = await latestConsentEvent(observer, provider, userId);
  assertEquals(latest.id, revocationId);
  assertEquals(latest.event_kind, "revoked");
  assertEquals(latest.consent_revision, revocationResult.event_revision);
  assertEquals(latest.causal_parent_id, revocationResult.accepted_parent_id);
}

Deno.test("Causal consent concurrency DB - overlapping grants and revocations are deny-wins", async () => {
  const label = "legalConsentConcurrencyDb";
  const clients = await connectClients(label, 3);
  if (clients == null) return;

  const [observer, grantClient, revokeClient] = clients;
  const suffix = crypto.randomUUID().slice(0, 8);
  const userId = crypto.randomUUID();
  const applicationNames = [
    `consent-grant-${suffix}`,
    `consent-revoke-${suffix}`,
  ];
  let blockerTransactionOpen = false;
  const pendingCalls: Promise<AppendResult>[] = [];

  try {
    if (!(await hasCausalConsentMigration(observer, label))) return;
    await insertUser(observer, userId, `Consent Concurrency ${suffix}`);
    await Promise.all([
      configureAuthenticatedCaller(
        grantClient,
        userId,
        applicationNames[0],
      ),
      configureAuthenticatedCaller(
        revokeClient,
        userId,
        applicationNames[1],
      ),
    ]);

    blockerTransactionOpen = true;
    await proveDenyWinsRace(
      observer,
      grantClient,
      revokeClient,
      "ai",
      userId,
      applicationNames,
      pendingCalls,
    );
    blockerTransactionOpen = false;

    blockerTransactionOpen = true;
    await proveDenyWinsRace(
      observer,
      grantClient,
      revokeClient,
      "analytics",
      userId,
      applicationNames,
      pendingCalls,
    );
    blockerTransactionOpen = false;
  } finally {
    if (blockerTransactionOpen) {
      await observer.queryArray("ROLLBACK").catch(() => {});
    }
    await Promise.allSettled(pendingCalls);
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
