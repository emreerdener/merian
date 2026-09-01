import { assert, assertStringIncludes } from "@std/assert";

const functionsRoot = new URL("../", import.meta.url);
const sharedHttpUrl = new URL("../_shared/http.ts", import.meta.url);
const edgeHandlerUrl = new URL("../_shared/edgeHandler.ts", import.meta.url);
const mediaBudgetsUrl = new URL("../_shared/mediaBudgets.ts", import.meta.url);
const revenueCatHandlerUrl = new URL(
  "../revenuecat-webhook/handler.ts",
  import.meta.url,
);
const flagIssueIndexUrl = new URL("../flag-issue/index.ts", import.meta.url);
const flagIssueDbUrl = new URL("../flag-issue/db.ts", import.meta.url);
const waitlistRouteUrl = new URL(
  "../../../../apps/web/app/api/waitlist/route.ts",
  import.meta.url,
);

Deno.test("production Edge routes do not bypass the bounded request readers", async () => {
  const offenders: string[] = [];
  const unwrappedEntrypoints: string[] = [];
  const missingLimit: string[] = [];
  let parserCallCount = 0;

  for await (const fileUrl of productionTypescriptFiles(functionsRoot)) {
    const source = await Deno.readTextFile(fileUrl);
    if (fileUrl.pathname.endsWith("/index.ts")) {
      const directlyWrappedUserHandler =
        /Deno\.serve\(\s*(?:async\s*)?\([^)]*\)\s*=>\s*withEdgeHandler\(/.test(
          source,
        );
      const registeredPublicHandler = /\bserveEdge\s*\(/.test(source);
      if (!directlyWrappedUserHandler && !registeredPublicHandler) {
        unwrappedEntrypoints.push(fileUrl.pathname);
      }
    }
    if (
      fileUrl.pathname !== sharedHttpUrl.pathname &&
      (
        /\b(?:req|request)(?:\.clone\(\))?\.(?:json|text|arrayBuffer|blob|formData)\s*\(/
          .test(source) ||
        /\b(?:req|request)\.body(?:\?)?\.getReader\s*\(/.test(source)
      )
    ) {
      offenders.push(fileUrl.pathname);
    }
    for (
      const call of source.matchAll(
        /\bparseJsonBody(?:<[^;{}()]*>)?\s*\(\s*(?:req|request)\s*,\s*\{([\s\S]*?)\}\s*\)/g,
      )
    ) {
      if (!/\blimit\s*:/.test(call[1])) {
        missingLimit.push(fileUrl.pathname);
      }
    }
    parserCallCount +=
      source.match(/\b(?:parseJsonBody|readRequestJsonWithinBudget)\s*</g)
        ?.length ?? 0;
    parserCallCount +=
      source.match(/\b(?:parseJsonBody|readRequestJsonWithinBudget)\s*\(/g)
        ?.length ?? 0;
  }

  assert(
    offenders.length === 0,
    `Direct request JSON/text readers bypass the byte boundary: ${
      offenders.join(", ")
    }`,
  );
  assert(
    missingLimit.length === 0,
    `parseJsonBody calls must select an endpoint limit: ${
      missingLimit.join(", ")
    }`,
  );
  assert(
    unwrappedEntrypoints.length === 0,
    `Custom-auth/public entrypoints must register through serveEdge: ${
      unwrappedEntrypoints.join(", ")
    }`,
  );
  assert(
    parserCallCount >= 60,
    `Expected broad bounded-parser coverage; found ${parserCallCount} calls.`,
  );
});

async function* productionTypescriptFiles(
  directoryUrl: URL,
): AsyncGenerator<URL> {
  for await (const entry of Deno.readDir(directoryUrl)) {
    if (entry.name.startsWith(".")) continue;
    if (entry.isDirectory && entry.name === "_tests") continue;
    const entryUrl = new URL(
      entry.name + (entry.isDirectory ? "/" : ""),
      directoryUrl,
    );
    if (entry.isDirectory) {
      yield* productionTypescriptFiles(entryUrl);
      continue;
    }
    if (
      entry.isFile &&
      entry.name.endsWith(".ts") &&
      !entry.name.endsWith(".test.ts") &&
      !entry.name.endsWith("_test.ts")
    ) {
      yield entryUrl;
    }
  }
}

Deno.test("shared body and error boundaries retain their security invariants", async () => {
  const [http, edgeHandler, mediaBudgets, revenueCat] = await Promise.all([
    Deno.readTextFile(sharedHttpUrl),
    Deno.readTextFile(edgeHandlerUrl),
    Deno.readTextFile(mediaBudgetsUrl),
    Deno.readTextFile(revenueCatHandlerUrl),
  ]);

  for (
    const fragment of [
      "JSON_BODY_LIMITS",
      "readByteStreamWithinLimit",
      "readRequestBodyWithinLimit",
      "readBoundedJsonBody",
      'new TextDecoder("utf-8", { fatal: true })',
      '"unsupported_media_type"',
      '"invalid_content_length"',
      "declaredBytes !== bytes.byteLength",
      "reader.cancel",
    ]
  ) {
    assertStringIncludes(http, fragment);
  }
  assert(
    !http.includes("const chunks: Uint8Array[]"),
    "Canonical request readers must not retain attacker-shaped chunk arrays.",
  );
  assertStringIncludes(edgeHandler, "error instanceof PublicHttpError");
  assertStringIncludes(edgeHandler, '"internal_error"');
  assertStringIncludes(edgeHandler, "finalizeEdgeResponse");
  assertStringIncludes(edgeHandler, "withPublicEdgeHandler");
  assertStringIncludes(edgeHandler, "serveEdge");
  assertStringIncludes(edgeHandler, "isExplicitPublicErrorResponse");
  assert(
    !edgeHandler.includes('"error": error.message'),
    "The shared handler must never serialize an exception message.",
  );
  assertStringIncludes(mediaBudgets, "readBoundedJsonBody<T>");
  assertStringIncludes(mediaBudgets, "readByteStreamWithinLimit(");
  assert(
    !mediaBudgets.includes("const chunks: Uint8Array[]"),
    "Media response readers must share the bounded byte accumulator.",
  );
  assertStringIncludes(revenueCat, "readRequestBodyWithinLimit(");
  assertStringIncludes(revenueCat, "isJsonMediaType(");
  assert(
    !revenueCat.includes("async function readBoundedBody"),
    "Signed webhooks must reuse the canonical raw byte reader.",
  );
});

Deno.test("flag-issue keeps owner flags separate from legacy post reports", async () => {
  const [indexSource, dbSource] = await Promise.all([
    Deno.readTextFile(flagIssueIndexUrl),
    Deno.readTextFile(flagIssueDbUrl),
  ]);

  const ownerSubmission = indexSource.indexOf("await submitOwnedFlagIssue(");
  const legacyResolution = indexSource.indexOf(
    "await resolveLegacyCommunityPostReport(",
  );
  const postReport = indexSource.indexOf("await upsertExplorePostReport(");
  assert(
    ownerSubmission >= 0 && legacyResolution > ownerSubmission &&
      postReport > legacyResolution,
    "flag-issue must try the atomic owner path before its legacy post-report bridge.",
  );
  for (
    const fragment of [
      'supabaseAdmin.rpc("submit_owned_flag_issue"',
      'flagReason === "Inappropriate content"',
      'userSuggestion === "Reported from Community request"',
      '.from("explore_community_requests")',
      '.select("id,post_id")',
      ".maybeSingle()",
      '"get_community_identification_detail"',
      "target_request_id: request.id",
      "detail.scan_id.toLowerCase() !== scanId.toLowerCase()",
      "detail.post_id.toLowerCase() !== request.post_id.toLowerCase()",
    ]
  ) {
    assertStringIncludes(dbSource, fragment);
  }
  assert(
    !dbSource.includes('.from("flagged_reviews")') &&
      !dbSource.includes('.from("scans")'),
    "flag-issue must not recreate the atomic owner mutation as sequential Edge writes.",
  );
});

Deno.test("public waitlist uses Turnstile and the atomic database RPC", async () => {
  const route = await Deno.readTextFile(waitlistRouteUrl);

  for (
    const fragment of [
      "readBoundedJsonObject(",
      "verifyTurnstileToken(",
      "waitlistIpHash(",
      '"claim_beta_waitlist_challenge_attempt"',
      'supabase.rpc("submit_beta_waitlist_signup"',
      '"waitlist_request_failed"',
      '"internal_error"',
      "has_turnstile_secret:",
      '"X-Request-ID"',
      '"Cache-Control": "private, no-store"',
    ]
  ) {
    assertStringIncludes(route, fragment);
  }
  assert(!route.includes("request.json("));
  assert(!route.includes('.from("beta_waitlist_signups")'));
  assert(!route.includes("SUPABASE_ANON_KEY"));

  const configurationUnavailable = route.indexOf(
    '"waitlist_security_configuration_unavailable"',
  );
  const serviceClient = route.indexOf("createAdminSupabaseClient()");
  const challengeRateClaim = route.indexOf(
    '"claim_beta_waitlist_challenge_attempt"',
  );
  const challengeVerification = route.indexOf(
    "await verifyTurnstileToken(",
  );
  const mutation = route.indexOf(
    'supabase.rpc("submit_beta_waitlist_signup"',
  );
  assert(
    configurationUnavailable >= 0 &&
      configurationUnavailable < serviceClient &&
      serviceClient < challengeRateClaim &&
      challengeRateClaim < challengeVerification &&
      challengeVerification < mutation,
    "Configuration must fail before database work; the distributed rate claim must run before Turnstile, and Turnstile must pass before insertion.",
  );
});
