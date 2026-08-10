import {
  assert,
  assertEquals,
  assertMatch,
  assertNotEquals,
  assertThrows,
} from "@std/assert";
import {
  applyRevenueCatPrelaunchReset,
  buildRevenueCatPrelaunchResetPlan,
  parseRevenueCatPrelaunchResetArgs,
  type RevenueCatPrelaunchResetCandidate,
  revenueCatPrelaunchResetPlanSHA256,
  runRevenueCatPrelaunchReset,
  validateRevenueCatPrelaunchResetAuthorization,
} from "./reset_revenuecat_customers_prelaunch.ts";

const EXPORT_PROJECT_ID = "49ebd1c2";
const V2_PROJECT_ID = `proj${EXPORT_PROJECT_ID}`;
const FIXTURE_PATH = new URL(
  "../tests/revenuecat_prelaunch_reset_customers_fixture.csv",
  import.meta.url,
).pathname;

Deno.test("prelaunch reset dry-run performs no network request", async () => {
  let requestCount = 0;
  const exitCode = await runRevenueCatPrelaunchReset([
    "--revenuecat-customers-csv",
    FIXTURE_PATH,
    "--project-id",
    V2_PROJECT_ID,
    "--export-project-id",
    EXPORT_PROJECT_ID,
  ], {
    now: new Date("2026-08-10T00:00:00Z"),
    fetcher: () => {
      requestCount += 1;
      throw new Error("dry-run must not call RevenueCat");
    },
  });

  assertEquals(exitCode, 0);
  assertEquals(requestCount, 0);
});

Deno.test("prelaunch reset plan includes every exact exported customer and surfaces evidence", () => {
  const plan = buildRevenueCatPrelaunchResetPlan({
    revenueCatSource: [
      "project_id;app_user_id;last_seen_at;custom_attributes;latest_product;total_spent;is_rc_promo;has_made_sandbox_purchase;latest_auto_renew_intent",
      `${EXPORT_PROJECT_ID};z-user;2026-08-09T00:00:00Z;;pro_monthly;0;false;true;f`,
      `${EXPORT_PROJECT_ID};a-user;2026-08-08T00:00:00Z;"{""email"":{""value"":""tester@example.com""}}";;0;false;false;f`,
    ].join("\n"),
    exportProjectID: EXPORT_PROJECT_ID,
  });

  assertEquals(
    plan.candidates.map((candidate) => candidate.app_user_id),
    ["a-user", "z-user"],
  );
  assertEquals(plan.purchaseOrEntitlementEvidenceCount, 1);
  assertEquals(plan.customerAttributeEvidenceCount, 1);
});

Deno.test("prelaunch reset plan rejects mixed projects, duplicates, and padded IDs", () => {
  const header = "project_id,app_user_id,custom_attributes";
  assertThrows(() =>
    buildRevenueCatPrelaunchResetPlan({
      revenueCatSource: [
        header,
        `${EXPORT_PROJECT_ID},same,`,
        `otherproject,same,`,
      ].join("\n"),
      exportProjectID: EXPORT_PROJECT_ID,
    })
  );
  assertThrows(() =>
    buildRevenueCatPrelaunchResetPlan({
      revenueCatSource: [
        header,
        `${EXPORT_PROJECT_ID},same,`,
        `${EXPORT_PROJECT_ID},same,`,
      ].join("\n"),
      exportProjectID: EXPORT_PROJECT_ID,
    })
  );
  assertThrows(() =>
    buildRevenueCatPrelaunchResetPlan({
      revenueCatSource: [header, `${EXPORT_PROJECT_ID}, padded ,`].join(
        "\n",
      ),
      exportProjectID: EXPORT_PROJECT_ID,
    })
  );
});

Deno.test("prelaunch reset arguments bind dashboard and V2 project identities", () => {
  const args = parseRevenueCatPrelaunchResetArgs([
    "--revenuecat-customers-csv",
    "customers.csv",
    "--project-id",
    V2_PROJECT_ID,
    "--export-project-id",
    EXPORT_PROJECT_ID,
    "--concurrency",
    "3",
  ]);
  assertEquals(args.projectID, V2_PROJECT_ID);
  assertEquals(args.exportProjectID, EXPORT_PROJECT_ID);
  assertEquals(args.concurrency, 3);
  assertThrows(() => parseRevenueCatPrelaunchResetArgs(["--concurrency", "4"]));
  assertThrows(() => parseRevenueCatPrelaunchResetArgs(["--unknown"]));
});

Deno.test("prelaunch reset digest binds source, projects, and exact candidates", async () => {
  const candidates = [candidate("customer-one")];
  const baseline = await revenueCatPrelaunchResetPlanSHA256({
    candidates,
    sourceSHA256: "a".repeat(64),
    projectID: V2_PROJECT_ID,
    exportProjectID: EXPORT_PROJECT_ID,
  });
  assertMatch(baseline, /^[0-9a-f]{64}$/);
  assertNotEquals(
    baseline,
    await revenueCatPrelaunchResetPlanSHA256({
      candidates,
      sourceSHA256: "b".repeat(64),
      projectID: V2_PROJECT_ID,
      exportProjectID: EXPORT_PROJECT_ID,
    }),
  );
  assertNotEquals(
    baseline,
    await revenueCatPrelaunchResetPlanSHA256({
      candidates: [candidate("customer-two")],
      sourceSHA256: "a".repeat(64),
      projectID: V2_PROJECT_ID,
      exportProjectID: EXPORT_PROJECT_ID,
    }),
  );
});

Deno.test("prelaunch reset apply requires digest, count, ledger, and both acknowledgements", () => {
  const args = parseRevenueCatPrelaunchResetArgs([
    "--revenuecat-customers-csv",
    "customers.csv",
    "--project-id",
    V2_PROJECT_ID,
    "--export-project-id",
    EXPORT_PROJECT_ID,
    "--results-csv",
    "results.csv",
    "--summary-json",
    "summary.json",
    "--approved-plan-sha256",
    "a".repeat(64),
    "--confirm-count",
    "1",
    "--apply",
  ]);

  assertThrows(() =>
    validateRevenueCatPrelaunchResetAuthorization({
      args,
      candidateSHA: "a".repeat(64),
      candidateCount: 1,
    })
  );
  args.confirmedReset = true;
  assertThrows(() =>
    validateRevenueCatPrelaunchResetAuthorization({
      args,
      candidateSHA: "a".repeat(64),
      candidateCount: 1,
    })
  );
  args.acknowledgedErasure = true;
  validateRevenueCatPrelaunchResetAuthorization({
    args,
    candidateSHA: "a".repeat(64),
    candidateCount: 1,
  });
  assertThrows(() =>
    validateRevenueCatPrelaunchResetAuthorization({
      args,
      candidateSHA: "b".repeat(64),
      candidateCount: 1,
    })
  );
});

Deno.test("prelaunch reset issues only exact DELETE requests and records terminal outcomes", async () => {
  const requests: Array<{
    method: string;
    url: string;
    authorization: string | null;
  }> = [];
  const statuses = [200, 202, 404, 403];
  const fakeFetch: typeof fetch = (input, init) => {
    requests.push({
      method: init?.method ?? "GET",
      url: String(input),
      authorization: new Headers(init?.headers).get("authorization"),
    });
    return Promise.resolve(
      new Response(null, { status: statuses[requests.length - 1] }),
    );
  };

  const candidates = [
    candidate("plain"),
    candidate("email+tag@example.com"),
    candidate("$RCAnonymousID:fixture"),
    candidate("forbidden"),
  ];
  const results = await applyRevenueCatPrelaunchReset({
    candidates,
    projectID: V2_PROJECT_ID,
    apiKey: "sk_fixture",
    concurrency: 1,
    fetcher: fakeFetch,
    sleep: () => Promise.resolve(),
  });

  assertEquals(
    results.map((entry) => entry.status),
    ["deleted", "queued", "already_absent", "failed"],
  );
  assertEquals(results[3].error_code, "delete_http_403");
  assertEquals(requests.map((request) => request.method), [
    "DELETE",
    "DELETE",
    "DELETE",
    "DELETE",
  ]);
  assert(
    requests.every((request) =>
      request.authorization === "Bearer sk_fixture" &&
      request.url.startsWith(
        `https://api.revenuecat.com/v2/projects/${V2_PROJECT_ID}/customers/`,
      ) && !request.url.includes("?")
    ),
  );
  assert(requests[1].url.endsWith("email%2Btag%40example.com"));
  assert(requests[2].url.endsWith("%24RCAnonymousID%3Afixture"));
});

Deno.test("prelaunch reset bounds retries without leaking response content", async () => {
  let requestCount = 0;
  const fakeFetch: typeof fetch = () => {
    requestCount += 1;
    return Promise.resolve(
      new Response("sensitive-provider-body", { status: 503 }),
    );
  };
  const results = await applyRevenueCatPrelaunchReset({
    candidates: [candidate("retry-me")],
    projectID: V2_PROJECT_ID,
    apiKey: "sk_fixture",
    concurrency: 1,
    fetcher: fakeFetch,
    sleep: () => Promise.resolve(),
  });

  assertEquals(requestCount, 3);
  assertEquals(results, [{
    app_user_id: "retry-me",
    status: "failed",
    error_code: "delete_http_503",
  }]);
});

function candidate(appUserID: string): RevenueCatPrelaunchResetCandidate {
  return {
    app_user_id: appUserID,
    export_project_id: EXPORT_PROJECT_ID,
    last_seen_at: "2026-08-09T00:00:00Z",
    has_purchase_or_entitlement_evidence: false,
    has_customer_attributes: false,
  };
}
