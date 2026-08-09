import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  buildRevenueCatCustomerAudit,
  canonicalUUID,
  parseRevenueCatCustomerAuditArgs,
} from "./audit_revenuecat_customers.ts";
import {
  applyBetaEntitlementGrants,
  isEntitlementActive,
  parseBetaEntitlementGrantArgs,
  selectBetaEntitlementCandidates,
  validateGrantExpiration,
} from "./grant_revenuecat_beta_entitlements.ts";
import {
  parseDelimitedText,
  serializeDelimitedRows,
} from "./revenuecat_csv.ts";

const USER_ONE = "123e4567-e89b-12d3-a456-426614174000";
const USER_TWO = "223e4567-e89b-12d3-a456-426614174001";

Deno.test("RevenueCat CSV parser handles semicolons, quoted JSON, and newlines", () => {
  const parsed = parseDelimitedText(
    "app_user_id;custom_attributes;note\n" +
      '"alias,one";"{""supabase_user_id"":{""value"":""abc""}}";"line 1\nline 2"\n',
  );

  assertEquals(parsed.delimiter, ";");
  assertEquals(parsed.rows[0].app_user_id, "alias,one");
  assertEquals(
    parsed.rows[0].custom_attributes,
    '{"supabase_user_id":{"value":"abc"}}',
  );
  assertEquals(parsed.rows[0].note, "line 1\nline 2");
});

Deno.test("RevenueCat CSV serializer round-trips explicit review data", () => {
  const serialized = serializeDelimitedRows(
    ["app_user_id", "status"],
    [{ app_user_id: "alias,one", status: 'needs "review"' }],
  );
  const parsed = parseDelimitedText(serialized);
  assertEquals(parsed.rows, [{
    app_user_id: "alias,one",
    status: 'needs "review"',
  }]);
});

Deno.test("RevenueCat customer audit is aggregate-safe and conservative", () => {
  const canonicalOne = USER_ONE.toUpperCase();
  const canonicalTwo = USER_TWO.toUpperCase();
  const old = "2026-05-01T00:00:00Z";
  const recent = "2026-08-08T00:00:00Z";
  const supabaseSource = [
    "id,subscription_tier,subscription_expires_at",
    `${USER_ONE},pro,`,
    `${USER_TWO},free,`,
  ].join("\n");
  const revenueCatSource = [
    "app_user_id;last_seen_at;latest_product;total_spent;is_rc_promo;custom_attributes",
    `${canonicalOne};${recent};;;false;`,
    `${USER_ONE};${old};;;false;`,
    `$RCAnonymousID:stale;${old};;;false;`,
    `323E4567-E89B-12D3-A456-426614174002;${old};pro_annual;;false;`,
    `tester@example.com;${old};;;false;"{""supabase_user_id"":{""value"":""${canonicalTwo}""}}"`,
    `stale-alias;${old};;;false;`,
    `423E4567-E89B-12D3-A456-426614174003;${recent};;;false;`,
  ].join("\n");

  const report = buildRevenueCatCustomerAudit({
    supabaseSource,
    revenueCatSource,
    inactiveDays: 30,
    now: new Date("2026-08-09T00:00:00Z"),
  });

  assertEquals(report.summary.supabase_user_count, 2);
  assertEquals(report.summary.revenuecat_customer_count, 7);
  assertEquals(
    report.summary.classification_counts.canonical_supabase_uuid,
    1,
  );
  assertEquals(
    report.summary.classification_counts.case_variant_supabase_uuid,
    1,
  );
  assertEquals(report.summary.classification_counts.revenuecat_anonymous, 1);
  assertEquals(report.summary.classification_counts.linked_alias, 1);
  assertEquals(report.summary.purchase_evidence_count, 1);
  assertEquals(report.summary.custom_attribute_link_count, 1);
  assertEquals(report.summary.supabase_users_with_canonical_customer_count, 1);
  assertEquals(
    report.summary.supabase_users_missing_canonical_customer_count,
    1,
  );
  assertEquals(report.summary.duplicate_identity_group_count, 1);
  assertEquals(report.summary.review_candidate_count, 3);
  assertEquals(report.summary.deletion_performed, false);

  const purchasedUnknown = report.rows.find((row) =>
    row.app_user_id.startsWith("323E")
  );
  assertEquals(purchasedUnknown?.recommendation, "keep_purchase_history");
  const linkedAlias = report.rows.find((row) =>
    row.app_user_id === "tester@example.com"
  );
  assertEquals(linkedAlias?.recommendation, "keep_linked_alias");
});

Deno.test("RevenueCat operation argument parsers reject unsafe inputs", () => {
  assertEquals(parseRevenueCatCustomerAuditArgs([]).inactiveDays, 30);
  assertThrows(() => parseRevenueCatCustomerAuditArgs(["--unknown"]));
  assertEquals(parseBetaEntitlementGrantArgs([]).entitlementID, "pro");
  assertEquals(parseBetaEntitlementGrantArgs([]).concurrency, 3);
  assertThrows(() => parseBetaEntitlementGrantArgs(["--concurrency", "6"]));
  assertThrows(() => parseBetaEntitlementGrantArgs(["--concurrency", "0"]));
  assertThrows(() =>
    parseBetaEntitlementGrantArgs(["--entitlement-id", "bad/id"])
  );
});

Deno.test("Beta selection uses canonical IDs and excludes timed Pro rows", () => {
  const source = [
    "id,subscription_tier,subscription_expires_at",
    `${USER_ONE},pro,`,
    `${USER_TWO},pro,2026-08-20T00:00:00Z`,
    "323e4567-e89b-12d3-a456-426614174002,free,",
  ].join("\n");

  assertEquals(selectBetaEntitlementCandidates(source), [{
    app_user_id: USER_ONE.toUpperCase(),
  }]);
  assertEquals(selectBetaEntitlementCandidates(source, true).length, 2);
  assertEquals(canonicalUUID(USER_ONE), USER_ONE.toUpperCase());
});

Deno.test("Beta grant expiration is finite and bounded", () => {
  const now = new Date("2026-08-09T00:00:00Z");
  assertEquals(
    validateGrantExpiration("2026-12-01T00:00:00Z", now),
    "2026-12-01T00:00:00.000Z",
  );
  assertThrows(() => validateGrantExpiration("2026-08-09T00:30:00Z", now));
  assertThrows(() => validateGrantExpiration("2028-08-09T00:00:00Z", now));
});

Deno.test("Beta grant skips active Pro and grants inactive canonical customers", async () => {
  const expiresAt = "2026-12-01T00:00:00.000Z";
  const requests: Array<{ url: string; method: string }> = [];
  const fakeFetch: typeof fetch = (input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    requests.push({ url, method });
    const isFirstUser = url.includes(USER_ONE.toUpperCase());
    const isGrant = method === "POST";
    const entitlements = isFirstUser || isGrant
      ? {
        pro: {
          expires_date: expiresAt,
          grace_period_expires_date: null,
        },
      }
      : {};
    return Promise.resolve(
      new Response(
        JSON.stringify({
          request_date_ms: Date.parse("2026-08-09T00:00:00Z"),
          subscriber: { entitlements },
        }),
        { status: isGrant ? 201 : 200 },
      ),
    );
  };

  const results = await applyBetaEntitlementGrants({
    candidates: [
      { app_user_id: USER_ONE.toUpperCase() },
      { app_user_id: USER_TWO.toUpperCase() },
    ],
    entitlementID: "pro",
    expiresAt,
    apiKey: "server-side-fixture-key",
    concurrency: 2,
    fetcher: fakeFetch,
  });

  assertEquals(results.map((result) => result.status), [
    "already_active",
    "granted",
  ]);
  assertEquals(
    requests.filter((request) => request.method === "GET").length,
    2,
  );
  assertEquals(
    requests.filter((request) => request.method === "POST").length,
    1,
  );
});

Deno.test("Beta entitlement activity accepts lifetime and future grants", () => {
  assert(
    isEntitlementActive(
      { subscriber: { entitlements: { pro: { expires_date: null } } } },
      "pro",
    ),
  );
  assert(
    !isEntitlementActive(
      {
        request_date_ms: Date.parse("2026-08-09T00:00:00Z"),
        subscriber: {
          entitlements: {
            pro: { expires_date: "2026-08-08T00:00:00Z" },
          },
        },
      },
      "pro",
    ),
  );
});

Deno.test("Beta grant failures remain per-customer and secret-free", async () => {
  const failingFetch: typeof fetch = () =>
    Promise.resolve(new Response(null, { status: 403 }));
  const results = await applyBetaEntitlementGrants({
    candidates: [{ app_user_id: USER_ONE.toUpperCase() }],
    entitlementID: "pro",
    expiresAt: "2026-12-01T00:00:00.000Z",
    apiKey: "server-side-fixture-key",
    concurrency: 1,
    fetcher: failingFetch,
  });
  assertEquals(results, [{
    app_user_id: USER_ONE.toUpperCase(),
    status: "failed",
    error_code: "http_403",
  }]);
});
