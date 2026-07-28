import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

const migration = await Deno.readTextFile(
  new URL(
    "../../migrations/20260728133835_disable_dwca_exports_for_launch.sql",
    import.meta.url,
  ),
);
const requestIndex = await Deno.readTextFile(
  new URL("../request-export-dwca/index.ts", import.meta.url),
);
const workerIndex = await Deno.readTextFile(
  new URL("../export-dwca/index.ts", import.meta.url),
);
const downloadIndex = await Deno.readTextFile(
  new URL("../download-dwca/index.ts", import.meta.url),
);
const downloadHandler = await Deno.readTextFile(
  new URL("../download-dwca/handler.ts", import.meta.url),
);
const featureFlags = await Deno.readTextFile(
  new URL(
    "../../../../apps/ios/Merian/Core/Utilities/FieldTripsAvailability.swift",
    import.meta.url,
  ),
);
const settings = await Deno.readTextFile(
  new URL(
    "../../../../apps/ios/Merian/Features/Profile/Settings/Views/SettingsTabView.swift",
    import.meta.url,
  ),
);
const deploymentWorkflow = await Deno.readTextFile(
  new URL("../../../../.github/workflows/deploy.yml", import.meta.url),
);

Deno.test("DwC-A launch gate is canonical, transactional, and default-off", () => {
  for (
    const expected of [
      "CREATE TABLE internal.dwca_export_release_control",
      "enabled BOOLEAN NOT NULL DEFAULT FALSE",
      "FOR SHARE",
      "CREATE TRIGGER a_enforce_dwca_export_intake_gate",
      "BEFORE INSERT ON public.export_jobs",
      "CREATE OR REPLACE FUNCTION public.get_dwca_export_release_state()",
      "CREATE OR REPLACE FUNCTION public.request_dwca_export_job",
      "PG_ADVISORY_XACT_LOCK",
      "jobs.created_at >=",
      "WHEN unique_violation",
      "violated_constraint = CONSTRAINT_NAME",
      "'idx_export_jobs_user_pending'",
      "'status', 'disabled'",
      "failure_code = 'feature_disabled'",
      "UPDATE internal.export_download_grants",
      "'feature_disabled'",
      "WHERE jobs.jobname = 'resume_dwca_exports_every_minute'",
      "PERFORM cron.unschedule(scheduled_job.jobid)",
      "RESET lock_timeout",
      "RESET statement_timeout",
    ]
  ) {
    assertStringIncludes(migration, expected);
  }
  assertEquals(
    migration.includes(
      "cron.unschedule('reconcile_dwca_archive_cleanup_every_five_minutes')",
    ),
    false,
  );
  assertEquals(
    migration.includes(
      "cron.schedule(\n    'resume_dwca_exports_every_minute'",
    ),
    false,
  );
  assertEquals(migration.includes("SET LOCAL"), false);
  assertEquals(migration.includes("\nBEGIN;\n"), false);
  assertEquals(migration.includes("\nCOMMIT;\n"), false);
});

Deno.test("all current application boundaries honor the canonical launch gate", () => {
  assertStringIncludes(requestIndex, '"feature_unavailable"');
  assertStringIncludes(requestIndex, 'disposition === "disabled"');
  assertStringIncludes(workerIndex, "fetchDwcaExportReleaseState");
  assertStringIncludes(workerIndex, 'disposition: "disabled"');
  assertStringIncludes(downloadHandler, "fetchDwcaExportReleaseState");
  assertStringIncludes(downloadHandler, "!releaseState.enabled");
  assertStringIncludes(downloadHandler, '{ status: "gone" }');
  assertEquals(downloadIndex.includes("fetchDwcaExportReleaseState"), false);
  assertStringIncludes(featureFlags, "case dwcaExports");
  assertStringIncludes(featureFlags, "case .dwcaExports:");
  assertStringIncludes(settings, "FeatureFlags.isEnabled(.dwcaExports)");
  assertStringIncludes(deploymentWorkflow, 'disposition == "disabled"');
  assertStringIncludes(deploymentWorkflow, ".release.enabled == false");
  assertStringIncludes(
    deploymentWorkflow,
    '"/functions/v1/reconcile-dwca-archive-cleanup"',
  );
});
