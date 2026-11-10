import { assert, assertEquals, assertStringIncludes } from "@std/assert";

const migration = await Deno.readTextFile(
  new URL(
    "../migrations/20261110190707_history_private_evidence_drain_health.sql",
    import.meta.url,
  ),
);
const workflow = await Deno.readTextFile(
  new URL(
    "../../../.github/workflows/observation-evidence-erasure-health-monitor.yml",
    import.meta.url,
  ),
);

Deno.test("private cleanup deployment is inactive until explicit activation", () => {
  assertStringIncludes(migration, "enabled BOOLEAN NOT NULL DEFAULT FALSE");
  assert(!/\bcron\.(schedule|alter_job)\s*\(/i.test(migration));
  assert(!/UPDATE\s+internal\.observation_history_rollout/i.test(migration));
  assertStringIncludes(
    workflow,
    "vars.EVIDENCE_ERASURE_MONITOR_ENABLED == 'true'",
  );
  assertStringIncludes(workflow, "github.ref == 'refs/heads/main'");
  assertStringIncludes(workflow, "PROJECT_ID: qlarqavoqhkuwzmevrmf");
  assertStringIncludes(workflow, "persist-credentials: false");
  assert(
    !/pull_request_target|secrets: inherit|contents: write/.test(workflow),
  );
});

Deno.test("service aggregate is the only newly granted API routine", () => {
  const grants = [
    ...migration.matchAll(/GRANT EXECUTE ON FUNCTION\s+([^;]+);/g),
  ].map((match) => match[1].replace(/\s+/g, " ").trim());
  assertEquals(grants, [
    "public.get_observation_evidence_erasure_health() TO service_role",
  ]);
  assertStringIncludes(migration, "PERFORM internal.require_service_role()");
  assertStringIncludes(migration, "SET statement_timeout = '5s'");
  assertStringIncludes(migration, "ADD COLUMN first_observed_at TIMESTAMPTZ;");
  assertStringIncludes(
    migration,
    "NEW.first_observed_at IS DISTINCT FROM OLD.first_observed_at",
  );
  assert(!/SET\s+first_observed_at\s*=/i.test(migration));
});

Deno.test("monitor cannot invoke mutation RPCs or dispatch transport", async () => {
  const source = await Deno.readTextFile(
    new URL("./monitor_observation_evidence_erasure.ts", import.meta.url),
  );
  assertEquals(
    [...source.matchAll(/\.rpc\(\s*"([^"]+)"/g)].map((match) => match[1]),
    ["get_observation_evidence_erasure_health"],
  );
  assertStringIncludes(source, "requestTimeoutMs: 15_000");
  assertStringIncludes(source, "maximumResponseBytes: 16_384");
  assert(!/\.from\(|\.insert\(|\.update\(|\.delete\(/.test(source));
});
