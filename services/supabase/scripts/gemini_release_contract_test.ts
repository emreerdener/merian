import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  buildGeminiReleaseConfiguration,
  type GeminiReleaseManifest,
  parseGeminiReleaseManifest,
  verifyGeminiReleaseSource,
} from "./gemini_release_contract.ts";
import { geminiSmokeDigest } from "../functions/_shared/ai/geminiSmokeCatalog.ts";
import { GEMINI_DEPLOYMENT_IDENTITIES } from "../functions/_shared/geminiDeploymentIdentity.ts";

const fixture = (): GeminiReleaseManifest => ({
  version: 1,
  release_id: "00000000-0000-4000-8000-000000000001",
  target: "abcdefghijklmnopqrst",
  backend_sha: "a".repeat(40),
  configuration_digest: "b".repeat(64),
  configuration_text: "{}",
  expected_previous_revision: 0,
  window_start: "2026-11-20T00:00:00Z",
  window_end: "2026-11-20T01:00:00Z",
  app: {
    version: "1.1.0",
    build: "100",
    source_fingerprint: "c".repeat(64),
    testflight_group: "Synthetic group",
    availability_checked_at: "2026-11-19T00:00:00Z",
  },
  authorization: {
    reference: "synthetic-explicit-release-authorization",
    backend_deployment: true,
    activation: true,
    provider_smokes: true,
    protective_suspension: true,
    spending_cap_microusd: 1_000_000,
  },
});

Deno.test("Gemini release authorization is closed and includes paid calls and protective suspension", () => {
  const m = fixture();
  assertEquals(parseGeminiReleaseManifest(JSON.stringify(m)), m);
  for (
    const patch of [
      { version: 2 },
      { target: "https://elsewhere.invalid" },
      { backend_sha: "main" },
      { expected_previous_revision: -1 },
      { window_end: "2026-11-22T01:00:00Z" },
      { model: "override" },
    ]
  ) {
    assertThrows(() =>
      parseGeminiReleaseManifest(JSON.stringify({ ...m, ...patch }))
    );
  }
  for (
    const field of [
      "backend_deployment",
      "activation",
      "provider_smokes",
      "protective_suspension",
    ]
  ) {
    assertThrows(() =>
      parseGeminiReleaseManifest(
        JSON.stringify({
          ...m,
          authorization: { ...m.authorization, [field]: false },
        }),
      )
    );
  }
});

Deno.test("Gemini release freezes deployed profiles, case budgets and exact function identities", async () => {
  const c = await buildGeminiReleaseConfiguration([]);
  const m = {
    ...fixture(),
    configuration_text: JSON.stringify(c),
    configuration_digest: await geminiSmokeDigest(c),
  };
  assertEquals(await verifyGeminiReleaseSource(m), c);
  assertEquals(c.required_functions, GEMINI_DEPLOYMENT_IDENTITIES);
  assert(c.smoke_cases.length >= 8);
  assertEquals(
    new Set(c.smoke_cases.map((c) => c.id)).size,
    c.smoke_cases.length,
  );
  assert(c.smoke_cases.every((c) => c.reservation_microusd > 0));
  assertEquals(c.evaluation.quality, "unmeasured");
  await assertRejects(() =>
    verifyGeminiReleaseSource({ ...m, configuration_digest: "f".repeat(64) })
  );
  await assertRejects(() =>
    verifyGeminiReleaseSource({
      ...m,
      authorization: { ...m.authorization, spending_cap_microusd: 1 },
    })
  );
  const tampered = {
    ...c,
    required_functions: { ...c.required_functions, identify: "f".repeat(64) },
  };
  const tamperedDigest = await geminiSmokeDigest(tampered);
  await assertRejects(() =>
    verifyGeminiReleaseSource({
      ...m,
      configuration_text: JSON.stringify(tampered),
      configuration_digest: tamperedDigest,
    })
  );
});

Deno.test("Gemini activation is the final manual release step under the production lock", async () => {
  const source = await Deno.readTextFile(
    new URL("../../../.github/workflows/deploy.yml", import.meta.url),
  );
  const final = source.indexOf(
    "- name: Activate and verify authorized Gemini routing",
  );
  assert(final > 0);
  const step = source.slice(final);
  assert(step.includes("github.event_name == 'workflow_dispatch'"));
  assert(step.includes("inputs.gemini_activation_release != ''"));
  assert(step.includes("git ls-remote origin refs/heads/main"));
  assert(step.includes("verify_production_release_holds.ts"));
  assert(step.includes("MERIAN_GITHUB_RELEASE_AUDIT_TOKEN"));
  assertEquals((step.match(/- name:/g) ?? []).length, 1);
  assert(!source.includes("testflight_poll"));
  const runner = await Deno.readTextFile(
    new URL("activate_gemini_release.ts", import.meta.url),
  );
  assert(
    runner.indexOf(
      "await recheckEligibility();",
      runner.indexOf("for (const smoke"),
    ) < runner.indexOf("SELECT internal.activate_gemini_release"),
  );
  assert(runner.includes("internal.suspend_gemini_release"));
});
