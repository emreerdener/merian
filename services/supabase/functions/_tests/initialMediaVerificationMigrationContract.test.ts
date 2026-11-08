import { assert, assertEquals } from "@std/assert";
const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20261011113000_prepare_initial_media_verification.sql",
    import.meta.url,
  ),
);
Deno.test("M2 remains service-only storage authority with no provider or activation mutation", () => {
  assertEquals(
    [...migration.matchAll(/CREATE FUNCTION public\.([a-z_]+)\(/g)].map((m) =>
      m[1]
    ),
    [
      "claim_initial_media_preparation",
      "settle_initial_media_verification",
      "get_initial_media_verification",
      "get_initial_media_backend",
    ],
  );
  assert(
    !/UPDATE internal\.initial_analysis_rollout|INSERT INTO internal\.initial_analysis_media_backends|finalize_ai_quota|settle_complimentary|commit_identification_invocation|net\.http|cron\.schedule/i
      .test(migration),
  );
  assert(
    migration.includes(
      "claim.expires_at<=floor(extract(epoch FROM clock_timestamp())*1000)::BIGINT",
    ),
  );
  assert(!/INSERT INTO internal\.initial_analysis_results/.test(migration));
  assert(migration.includes("internal.initial_media_pending(p_scan)"));
  const resolver =
    migration.split("CREATE FUNCTION public.get_initial_media_backend")[1]
      .split("REVOKE ALL")[0];
  assert(
    !/initial_analysis_submissions|public\.users|initial_analysis_rollout/.test(
      resolver,
    ),
  );
});
