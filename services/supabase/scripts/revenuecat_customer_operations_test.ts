import { assert, assertEquals, assertThrows } from "@std/assert";
import {
  buildRevenueCatCustomerAudit,
  canonicalUUID,
  parseRevenueCatCustomerAuditArgs,
} from "./audit_revenuecat_customers.ts";
import {
  applyBetaEntitlementGrants,
  executeBetaEntitlementGrant,
  isEntitlementActive,
  parseBetaEntitlementGrantArgs,
  selectBetaEntitlementCandidates,
  sha256Hex,
  validateGrantExpiration,
} from "./grant_revenuecat_beta_entitlements.ts";
import {
  parseDelimitedText,
  serializeDelimitedRows,
} from "./revenuecat_csv.ts";
import {
  buildRevenueCatShellCleanupPlan,
  hasCustomerInfoHistory,
  parseRevenueCatShellCleanupArgs,
  revalidateAndDeleteRevenueCatShell,
  revenueCatShellCandidateSHA256,
  type RevenueCatShellCleanupCandidate,
} from "./cleanup_revenuecat_customer_shells.ts";

const USER_ONE = "123e4567-e89b-12d3-a456-426614174000";
const USER_TWO = "223e4567-e89b-12d3-a456-426614174001";
const USER_THREE = "323e4567-e89b-12d3-a456-426614174002";
const USER_FOUR = "423e4567-e89b-12d3-a456-426614174003";

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

Deno.test("RevenueCat customer audit rejects duplicate provider IDs", () => {
  assertThrows(() =>
    buildRevenueCatCustomerAudit({
      supabaseSource: ["id", USER_ONE].join("\n"),
      revenueCatSource: [
        "app_user_id,last_seen_at",
        `${USER_ONE.toUpperCase()},2026-07-01T00:00:00Z`,
        `${USER_ONE.toUpperCase()},2026-07-02T00:00:00Z`,
      ].join("\n"),
      inactiveDays: 7,
      now: new Date("2026-08-09T00:00:00Z"),
    })
  );
});

Deno.test("RevenueCat operation argument parsers reject unsafe inputs", () => {
  assertEquals(parseRevenueCatCustomerAuditArgs([]).inactiveDays, 30);
  assertThrows(() => parseRevenueCatCustomerAuditArgs(["--unknown"]));
  assertEquals(parseBetaEntitlementGrantArgs([]).entitlementID, "pro");
  assertEquals(parseBetaEntitlementGrantArgs([]).concurrency, 3);
  assertEquals(
    parseBetaEntitlementGrantArgs([
      "--users-csv",
      "users.csv",
      "--cohort-csv",
      "cohort.csv",
      "--auth-audit-csv",
      "auth.csv",
    ]).cohortCsvPath,
    "cohort.csv",
  );
  assertThrows(() => parseBetaEntitlementGrantArgs(["--concurrency", "6"]));
  assertThrows(() => parseBetaEntitlementGrantArgs(["--concurrency", "0"]));
  assertThrows(() =>
    parseBetaEntitlementGrantArgs(["--entitlement-id", "bad/id"])
  );
  assertThrows(() => parseBetaEntitlementGrantArgs(["--include-timed-pro"]));
  assertEquals(parseRevenueCatShellCleanupArgs([]).inactiveDays, 7);
  assertEquals(parseRevenueCatShellCleanupArgs([]).concurrency, 2);
  assertEquals(
    parseRevenueCatShellCleanupArgs([
      "--auth-audit-csv",
      "ghost-audit.csv",
    ]).authAuditCsvPath,
    "ghost-audit.csv",
  );
  assertThrows(() => parseRevenueCatShellCleanupArgs(["--concurrency", "4"]));
});

Deno.test("RevenueCat shell cleanup plan protects canonical users, cohort, history, and aliases", async () => {
  const canonicalOne = USER_ONE.toUpperCase();
  const canonicalTwo = USER_TWO.toUpperCase();
  const old = "2026-07-01T00:00:00Z";
  const recent = "2026-08-08T12:00:00Z";
  const supabaseSource = [
    "id,subscription_tier",
    `${USER_ONE},free`,
    `${USER_TWO},free`,
  ].join("\n");
  const revenueCatSource = [
    "app_user_id;last_seen_at;latest_product;custom_attributes",
    `${canonicalOne};${old};;`,
    `${USER_ONE};${old};;`,
    `${canonicalTwo};${old};;`,
    `$RCAnonymousID:stale;${old};;`,
    `unknown-shell;${old};;`,
    `recent-shell;${recent};;`,
    `purchased-shell;${old};pro_annual;`,
    `linked-shell;${old};;"{""supabase_user_id"":{""value"":""${canonicalOne}""}}"`,
    `${USER_THREE.toUpperCase()};${old};;`,
  ].join("\n");
  const authAuditSource = [
    "user_id,auth_exists,public_user_exists",
    `${USER_ONE},true,true`,
    `${USER_TWO},true,true`,
    `${USER_THREE},true,false`,
  ].join("\n");

  const plan = buildRevenueCatShellCleanupPlan({
    supabaseSource,
    authAuditSource,
    revenueCatSource,
    protectedCohortSource: ["id", USER_TWO].join("\n"),
    inactiveDays: 7,
    includeCurrentSupabaseShells: false,
    now: new Date("2026-08-09T00:00:00Z"),
  });

  assertEquals(
    plan.candidates.map((candidate) => candidate.app_user_id).sort(),
    [USER_ONE, "$RCAnonymousID:stale", "unknown-shell"].sort(),
  );
  assertEquals(
    (await revenueCatShellCandidateSHA256(plan.candidates)).length,
    64,
  );
});

Deno.test("RevenueCat shell cleanup can explicitly include inactive orphaned Supabase shells", () => {
  const plan = buildRevenueCatShellCleanupPlan({
    supabaseSource: [
      "id,subscription_tier",
      `${USER_ONE},free`,
      `${USER_TWO},free`,
    ].join("\n"),
    authAuditSource: [
      "user_id,auth_exists,public_user_exists",
      `${USER_ONE},false,true`,
      `${USER_TWO},true,true`,
    ].join("\n"),
    revenueCatSource: [
      "app_user_id,last_seen_at",
      `${USER_ONE.toUpperCase()},2026-07-01T00:00:00Z`,
    ].join("\n"),
    protectedCohortSource: ["id", USER_TWO].join("\n"),
    inactiveDays: 7,
    includeCurrentSupabaseShells: true,
    now: new Date("2026-08-09T00:00:00Z"),
  });

  assertEquals(plan.candidates.length, 1);
  assertEquals(plan.candidates[0].reason, "inactive_current_supabase_shell");
});

Deno.test("RevenueCat shell cleanup always protects active canonical Auth users", () => {
  const plan = buildRevenueCatShellCleanupPlan({
    supabaseSource: [
      "id,subscription_tier",
      `${USER_ONE},free`,
      `${USER_TWO},free`,
    ].join("\n"),
    authAuditSource: [
      "user_id,auth_exists,public_user_exists",
      `${USER_ONE},true,true`,
      `${USER_TWO},true,true`,
    ].join("\n"),
    revenueCatSource: [
      "app_user_id,last_seen_at",
      `${USER_ONE.toUpperCase()},2026-07-01T00:00:00Z`,
    ].join("\n"),
    protectedCohortSource: ["id", USER_TWO].join("\n"),
    inactiveDays: 7,
    includeCurrentSupabaseShells: true,
    now: new Date("2026-08-09T00:00:00Z"),
  });

  assertEquals(plan.candidates, []);
});

Deno.test("RevenueCat live cleanup revalidates an empty shell before queued deletion", async () => {
  const candidate = cleanupCandidate("stale-shell");
  const requests: Array<{ method: string; url: string }> = [];
  const fakeFetch: typeof fetch = (input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    requests.push({ method, url });
    if (method === "DELETE") {
      return Promise.resolve(new Response("{}", { status: 202 }));
    }
    if (url.includes("/aliases")) {
      return Promise.resolve(jsonResponse({
        object: "list",
        items: [{ object: "customer.alias", id: candidate.app_user_id }],
        next_page: null,
      }));
    }
    if (url.includes("/v1/subscribers/")) {
      return Promise.resolve(
        jsonResponse(emptyCustomerInfo(candidate.app_user_id)),
      );
    }
    return Promise.resolve(jsonResponse({
      object: "customer",
      id: candidate.app_user_id,
      project_id: "projtest1234",
      last_seen_at: Date.parse(candidate.last_seen_at),
      active_entitlements: { object: "list", items: [], next_page: null },
      attributes: { object: "list", items: [], next_page: null },
    }));
  };

  const result = await revalidateAndDeleteRevenueCatShell({
    candidate,
    protectedCohort: new Set(),
    inactiveBeforeMs: Date.parse("2026-08-02T00:00:00Z"),
    projectID: "projtest1234",
    apiKey: "sk_fixture",
    fetcher: fakeFetch,
    sleep: () => Promise.resolve(),
  });

  assertEquals(result.status, "queued");
  assertEquals(requests.map((request) => request.method), [
    "GET",
    "GET",
    "GET",
    "DELETE",
  ]);
});

Deno.test("RevenueCat live cleanup preserves any customer history and never deletes", async () => {
  const candidate = cleanupCandidate("stale-shell");
  const methods: string[] = [];
  const fakeFetch: typeof fetch = (input, init) => {
    const url = String(input);
    methods.push(init?.method ?? "GET");
    if (url.includes("/aliases")) {
      return Promise.resolve(jsonResponse({
        items: [{ object: "customer.alias", id: candidate.app_user_id }],
        next_page: null,
      }));
    }
    if (url.includes("/v1/subscribers/")) {
      const customerInfo = emptyCustomerInfo(candidate.app_user_id);
      customerInfo.subscriber.subscriptions = {
        pro_annual: { expires_date: null },
      };
      return Promise.resolve(jsonResponse(customerInfo));
    }
    return Promise.resolve(jsonResponse({
      object: "customer",
      id: candidate.app_user_id,
      project_id: "projtest1234",
      last_seen_at: Date.parse(candidate.last_seen_at),
      active_entitlements: { items: [], next_page: null },
      attributes: { items: [], next_page: null },
    }));
  };

  const result = await revalidateAndDeleteRevenueCatShell({
    candidate,
    protectedCohort: new Set(),
    inactiveBeforeMs: Date.parse("2026-08-02T00:00:00Z"),
    projectID: "projtest1234",
    apiKey: "sk_fixture",
    fetcher: fakeFetch,
    sleep: () => Promise.resolve(),
  });

  assertEquals(result.status, "protected_live_evidence");
  assertEquals(methods.includes("DELETE"), false);
  assert(
    hasCustomerInfoHistory(
      { subscriber: customerInfoSubscriber(candidate.app_user_id, true) },
      candidate.app_user_id,
    ),
  );
});

Deno.test("RevenueCat cleanup treats free-app install metadata as an empty purchase shell", () => {
  assertEquals(
    hasCustomerInfoHistory(
      {
        subscriber: {
          entitlements: {},
          subscriptions: {},
          non_subscriptions: {},
          other_purchases: {},
          original_app_user_id: "stale-shell",
          original_application_version: "1.0",
          original_purchase_date: "2026-01-01T00:00:00Z",
          management_url: null,
        },
      },
      "stale-shell",
    ),
    false,
  );
});

Deno.test("RevenueCat live cleanup protects a shell seen after its reviewed export", async () => {
  const candidate = cleanupCandidate("stale-shell");
  let requestCount = 0;
  const result = await revalidateAndDeleteRevenueCatShell({
    candidate,
    protectedCohort: new Set(),
    inactiveBeforeMs: Date.parse("2026-08-02T00:00:00Z"),
    projectID: "projtest1234",
    apiKey: "sk_fixture",
    fetcher: () => {
      requestCount += 1;
      return Promise.resolve(jsonResponse({
        object: "customer",
        id: candidate.app_user_id,
        project_id: "projtest1234",
        last_seen_at: Date.parse("2026-08-08T00:00:00Z"),
        active_entitlements: { items: [], next_page: null },
        attributes: { items: [], next_page: null },
      }));
    },
    sleep: () => Promise.resolve(),
  });

  assertEquals(result.status, "protected_live_evidence");
  assertEquals(requestCount, 1);
});

Deno.test("RevenueCat live cleanup protects newly linked Supabase attributes", async () => {
  const candidate = cleanupCandidate("stale-shell");
  let requestCount = 0;
  const result = await revalidateAndDeleteRevenueCatShell({
    candidate,
    protectedCohort: new Set([USER_ONE.toUpperCase()]),
    inactiveBeforeMs: Date.parse("2026-08-02T00:00:00Z"),
    projectID: "projtest1234",
    apiKey: "sk_fixture",
    fetcher: () => {
      requestCount += 1;
      return Promise.resolve(jsonResponse({
        object: "customer",
        id: candidate.app_user_id,
        project_id: "projtest1234",
        last_seen_at: Date.parse(candidate.last_seen_at),
        active_entitlements: { items: [], next_page: null },
        attributes: {
          items: [{
            object: "customer.attribute",
            name: "supabase_user_id",
            value: USER_ONE,
          }],
          next_page: null,
        },
      }));
    },
    sleep: () => Promise.resolve(),
  });

  assertEquals(result.status, "protected_live_evidence");
  assertEquals(requestCount, 1);
});

Deno.test("Beta selection is explicit and independent of current projection", () => {
  const usersSource = [
    "id,subscription_tier,subscription_expires_at",
    `${USER_ONE},free,`,
    `${USER_TWO},pro,2026-08-20T00:00:00Z`,
    `${USER_THREE},pro,`,
    `${USER_FOUR},pro,`,
  ].join("\n");
  const cohortSource = ["id", USER_ONE, USER_TWO, USER_THREE].join("\n");
  const authAuditSource = [
    "user_id,auth_exists,auth_is_anonymous",
    `${USER_ONE},true,true`,
    `${USER_TWO},true,false`,
    `${USER_THREE},true,false`,
    `${USER_FOUR},true,false`,
  ].join("\n");

  const selection = selectBetaEntitlementCandidates({
    usersSource,
    cohortSource,
    authAuditSource,
  });

  assertEquals(selection, {
    candidates: [USER_ONE, USER_TWO, USER_THREE].map((appUserID) => ({
      app_user_id: appUserID.toUpperCase(),
    })),
    verifiedAuthUserCount: 3,
    verifiedGhostCount: 1,
    verifiedLinkedCount: 2,
    projectionCounts: {
      free: 1,
      timed_pro: 1,
      permanent_pro: 1,
    },
  });
  assertEquals(canonicalUUID(USER_ONE), USER_ONE.toUpperCase());
});

Deno.test("Beta selection accepts Ghosts but rejects malformed, duplicate, and unverifiable rows", () => {
  const usersSource = [
    "id,subscription_tier,subscription_expires_at",
    `${USER_ONE},free,`,
    `${USER_TWO},pro,`,
  ].join("\n");
  const permanentAuthSource = [
    "user_id,auth_exists,auth_is_anonymous",
    `${USER_ONE},true,false`,
    `${USER_TWO},true,false`,
  ].join("\n");

  assertThrows(() =>
    selectBetaEntitlementCandidates({
      usersSource,
      cohortSource: ["id", "not-a-uuid"].join("\n"),
      authAuditSource: permanentAuthSource,
    })
  );
  assertThrows(() =>
    selectBetaEntitlementCandidates({
      usersSource,
      cohortSource: ["id", USER_ONE, USER_ONE.toUpperCase()].join("\n"),
      authAuditSource: permanentAuthSource,
    })
  );
  const invalidAuthError = assertThrows(() =>
    selectBetaEntitlementCandidates({
      usersSource,
      cohortSource: ["id", USER_ONE].join("\n"),
      authAuditSource: [
        "user_id,auth_exists,auth_is_anonymous",
        `${USER_ONE},true,unknown`,
      ].join("\n"),
    })
  );
  assert(invalidAuthError instanceof Error);
  assert(!invalidAuthError.message.includes(USER_ONE));
  assertThrows(() =>
    selectBetaEntitlementCandidates({
      usersSource,
      cohortSource: ["id", USER_TWO].join("\n"),
      authAuditSource: [
        "user_id,auth_exists,auth_is_anonymous",
        `${USER_ONE},true,false`,
      ].join("\n"),
    })
  );
});

Deno.test("Beta cohort checksum is deterministic", async () => {
  const source = ["id", USER_ONE].join("\n");
  assertEquals(await sha256Hex(source), await sha256Hex(source));
  assertEquals(
    await sha256Hex(source),
    await sha256Hex(new TextEncoder().encode(source)),
  );
  assertEquals((await sha256Hex(source)).length, 64);
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

Deno.test("Beta grant dry-run performs zero RevenueCat requests", async () => {
  let requestCount = 0;
  const unexpectedFetch: typeof fetch = () => {
    requestCount += 1;
    throw new Error("Dry-run must not call RevenueCat.");
  };

  const results = await executeBetaEntitlementGrant({
    apply: false,
    candidates: [{ app_user_id: USER_ONE.toUpperCase() }],
    entitlementID: "pro",
    expiresAt: null,
    apiKey: null,
    concurrency: 1,
    fetcher: unexpectedFetch,
  });

  assertEquals(requestCount, 0);
  assertEquals(results, [{
    app_user_id: USER_ONE.toUpperCase(),
    status: "planned",
    error_code: "",
  }]);
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

Deno.test("Beta grant accepts get-or-create 201 and posts exactly once", async () => {
  const expiresAt = "2026-12-01T00:00:00.000Z";
  const requests: Array<{ url: string; method: string }> = [];
  const fakeFetch: typeof fetch = (input, init) => {
    const method = init?.method ?? "GET";
    requests.push({ url: String(input), method });
    const entitlements = method === "POST"
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
        { status: 201 },
      ),
    );
  };

  const results = await applyBetaEntitlementGrants({
    candidates: [{ app_user_id: USER_ONE.toUpperCase() }],
    entitlementID: "pro",
    expiresAt,
    apiKey: "server-side-fixture-key",
    concurrency: 1,
    fetcher: fakeFetch,
  });

  assertEquals(results[0].status, "granted");
  assertEquals(requests.map((request) => request.method), ["GET", "POST"]);
});

Deno.test("Beta grant still requires promotional POST 201", async () => {
  const fakeFetch: typeof fetch = () =>
    Promise.resolve(
      new Response(
        JSON.stringify({ subscriber: { entitlements: {} } }),
        { status: 200 },
      ),
    );

  const results = await applyBetaEntitlementGrants({
    candidates: [{ app_user_id: USER_ONE.toUpperCase() }],
    entitlementID: "pro",
    expiresAt: "2026-12-01T00:00:00.000Z",
    apiKey: "server-side-fixture-key",
    concurrency: 1,
    fetcher: fakeFetch,
  });

  assertEquals(results[0].error_code, "http_200");
});

Deno.test("Beta grant sends requests only for explicit cohort members", async () => {
  const usersSource = [
    "id,subscription_tier,subscription_expires_at",
    `${USER_ONE},free,`,
    `${USER_TWO},pro,`,
  ].join("\n");
  const authAuditSource = [
    "user_id,auth_exists,auth_is_anonymous",
    `${USER_ONE},true,false`,
    `${USER_TWO},true,false`,
  ].join("\n");
  const selection = selectBetaEntitlementCandidates({
    usersSource,
    cohortSource: ["id", USER_ONE].join("\n"),
    authAuditSource,
  });
  const requestedURLs: string[] = [];
  const activeFetch: typeof fetch = (input) => {
    requestedURLs.push(String(input));
    return Promise.resolve(
      new Response(
        JSON.stringify({
          subscriber: {
            entitlements: { pro: { expires_date: null } },
          },
        }),
        { status: 200 },
      ),
    );
  };

  await executeBetaEntitlementGrant({
    apply: true,
    candidates: selection.candidates,
    entitlementID: "pro",
    expiresAt: "2026-12-01T00:00:00.000Z",
    apiKey: "server-side-fixture-key",
    concurrency: 1,
    fetcher: activeFetch,
  });

  assertEquals(requestedURLs.length, 1);
  assert(requestedURLs[0].includes(USER_ONE.toUpperCase()));
  assert(!requestedURLs[0].includes(USER_TWO.toUpperCase()));
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

Deno.test("Beta grant bounds retryable RevenueCat failures", async () => {
  let requestCount = 0;
  const retryableFetch: typeof fetch = () => {
    requestCount += 1;
    return Promise.resolve(new Response(null, { status: 503 }));
  };
  const results = await applyBetaEntitlementGrants({
    candidates: [{ app_user_id: USER_ONE.toUpperCase() }],
    entitlementID: "pro",
    expiresAt: "2026-12-01T00:00:00.000Z",
    apiKey: "server-side-fixture-key",
    concurrency: 1,
    fetcher: retryableFetch,
  });

  assertEquals(requestCount, 3);
  assertEquals(results[0].error_code, "http_503");
});

function cleanupCandidate(
  appUserID: string,
): RevenueCatShellCleanupCandidate {
  return {
    app_user_id: appUserID,
    classification: "unlinked_alias",
    linked_supabase_user_id: "",
    last_seen_at: "2026-07-01T00:00:00.000Z",
    inactive_days: 39,
    reason: "inactive_unlinked_alias",
  };
}

function jsonResponse(value: unknown): Response {
  return new Response(JSON.stringify(value), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

function customerInfoSubscriber(appUserID: string, withSubscription = false) {
  return {
    entitlements: {},
    subscriptions: withSubscription ? { pro_annual: {} } : {},
    non_subscriptions: {},
    other_purchases: {},
    original_app_user_id: appUserID,
    original_application_version: null,
    original_purchase_date: null,
    management_url: null,
  };
}

function emptyCustomerInfo(appUserID: string) {
  return {
    subscriber: customerInfoSubscriber(appUserID),
  };
}
