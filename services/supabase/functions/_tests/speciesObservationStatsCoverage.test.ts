import { assert, assertStringIncludes } from "@std/assert";

const dbUrl = new URL(
  "../species-observation-stats/db.ts",
  import.meta.url,
);
const indexUrl = new URL(
  "../species-observation-stats/index.ts",
  import.meta.url,
);
const securityUrl = new URL(
  "../species-observation-stats/security.ts",
  import.meta.url,
);
const configUrl = new URL("../../config.toml", import.meta.url);

Deno.test("public species stats route retains every resource boundary", async () => {
  const [db, index, security, config] = await Promise.all([
    Deno.readTextFile(dbUrl),
    Deno.readTextFile(indexUrl),
    Deno.readTextFile(securityUrl),
    Deno.readTextFile(configUrl),
  ]);

  for (
    const fragment of [
      "Missing required parameter: species_id",
      "authorizeSpeciesObservationStatsRequest(",
      "claimSpeciesObservationStatsPopulation(",
      "finalizeSpeciesObservationStatsPopulation(",
      ".abortSignal(AbortSignal.timeout(DATABASE_TIMEOUT_MS))",
      "fetchWithDeadline(",
      "OutboundRequestTimeoutError",
      "{ fetcher, timeoutMs }",
      "readResponseArrayBufferWithinBudget(",
      "MAX_PROVIDER_RESPONSE_BYTES",
    ]
  ) {
    assertStringIncludes(db, fragment);
  }
  assert(
    !db.includes('paramName: "taxon_name"'),
    "Observation queries must never fall back to caller-controlled taxon_name.",
  );
  assertStringIncludes(
    security,
    '"merian-species-stats-ip-v1"',
  );
  assertStringIncludes(
    security,
    '"authorize_species_observation_stats_request"',
  );
  assertStringIncludes(
    security,
    '"preflight_species_observation_stats_request"',
  );
  assert(
    security.indexOf("await preflightSpeciesObservationStatsRequest(") <
      security.indexOf(
        "const userId = await optionalAuthenticatedUserId(",
      ),
    "The IP budget must be charged before optional user-token validation.",
  );
  assertStringIncludes(index, "resolveSpeciesObservationStatsSecurityContext");
  assertStringIncludes(index, "readRequestJsonWithinBudget");
  assertStringIncludes(index, "MAX_REQUEST_BODY_BYTES = 4 * 1024");
  assertStringIncludes(index, '"Cache-Control": "private, no-store"');
  const publicCacheHeaders = index.slice(
    index.indexOf("const freshStatsCacheHeaders"),
    index.indexOf("const privateErrorHeaders"),
  );
  assertStringIncludes(publicCacheHeaders, '"Vary": "Accept-Encoding"');
  assert(
    !publicCacheHeaders.includes("Authorization"),
    "Identity-independent public responses must not fragment cache entries by bearer token.",
  );

  const configSection = config.slice(
    config.indexOf("[functions.species-observation-stats]"),
    config.indexOf(
      "\n[functions.",
      config.indexOf("[functions.species-observation-stats]") + 1,
    ),
  );
  assertStringIncludes(configSection, "verify_jwt = false");
});
