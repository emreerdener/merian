import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  COMPARISON_PROJECT,
  COMPARISON_SECRET,
  comparisonConfiguration,
  ComparisonControlError,
  type ComparisonControlRuntime,
  controlAudioComparison,
  requireComparisonWorkflow,
} from "./control_audio_comparison.ts";
import { sha256Hex } from "./verify_edge_secret_digest.ts";
import { AUDIO_COMPARISON_PLAN_SHA256 } from "../functions/identify-multimodal/comparison/plan.ts";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../functions/identify-multimodal/deploymentIdentity.ts";
import {
  audioComparisonScanId,
  resolveAudioComparison,
} from "../functions/identify-multimodal/comparison/assignment.ts";

const NOW = Date.parse("2026-09-23T22:00:00.000Z");
const OWNER = "11111111-1111-4111-8111-111111111111";
const SOURCE = "a".repeat(40);
const DEPLOYED = "b".repeat(40);
function config(overrides: Record<string, unknown> = {}) {
  return JSON.stringify({
    version: 1,
    ownerId: OWNER,
    planSha256: AUDIO_COMPARISON_PLAN_SHA256,
    backendBundleSha256: IDENTIFICATION_BUNDLE_SHA256,
    startsAt: "2026-09-23T22:00:00.000Z",
    expiresAt: "2026-09-24T00:00:00.000Z",
    ...overrides,
  });
}
function request(
  operation: "inspect" | "activate" | "deactivate",
  raw = config(),
) {
  return {
    operation,
    sourceSha: SOURCE,
    deployedSha: DEPLOYED,
    privateConfiguration: raw,
  };
}
function fake() {
  const state = {
    now: NOW,
    digest: null as string | null,
    sets: [] as string[],
    unsets: 0,
    lists: 0,
  };
  const runtime: ComparisonControlRuntime = {
    now: () => state.now,
    list: () => {
      state.lists++;
      return Promise.resolve(
        state.digest === null ? [] : [{
          name: COMPARISON_SECRET,
          value: state.digest,
        }],
      );
    },
    set: async (input) => {
      state.sets.push(input);
      const prefix = `${COMPARISON_SECRET}='`;
      assert(input.startsWith(prefix) && input.endsWith("'\n"));
      state.digest = await sha256Hex(input.slice(prefix.length, -2));
    },
    unset: () => {
      state.unsets++;
      state.digest = null;
      return Promise.resolve();
    },
  };
  return { state, runtime };
}

Deno.test("comparison control leaves absent configuration disabled without private input", async () => {
  for (const operation of ["inspect", "deactivate"] as const) {
    const { state, runtime } = fake();
    const evidence = await controlAudioComparison(
      request(operation, ""),
      runtime,
    );
    assertEquals(evidence.status, "disabled");
    assertEquals(evidence.configurationPresent, false);
    assertEquals(state.sets.length + state.unsets, 0);
  }
});

Deno.test("comparison activation is bounded, redacted and idempotent; deactivation verifies absence", async () => {
  const { state, runtime } = fake();
  const active = await controlAudioComparison(request("activate"), runtime);
  assertEquals(active.status, "active");
  assertEquals(active.target, COMPARISON_PROJECT);
  assertEquals(active.automaticIdentificationRequests, 0);
  assertEquals(state.sets.length, 1);
  const encoded = JSON.stringify(active);
  assert(!encoded.includes(OWNER));
  assert(!encoded.includes(state.digest!));
  assert(!encoded.includes("ownerId"));
  const again = await controlAudioComparison(request("activate"), runtime);
  assertEquals(again.status, "already_active");
  assertEquals(again.mutationAttempted, false);
  assertEquals(state.sets.length, 1);
  const disabled = await controlAudioComparison(request("deactivate"), runtime);
  assertEquals(disabled.status, "disabled");
  assertEquals(disabled.cleanup, "verified_absent");
  assertEquals(state.digest, null);
  assertEquals(state.unsets, 1);
});

Deno.test("an expired stored configuration is inert and remains removable after plan or bundle changes", async () => {
  const { state, runtime } = fake();
  await controlAudioComparison(request("activate"), runtime);
  state.now = Date.parse("2026-09-24T00:00:00.000Z");
  const expired = await controlAudioComparison(request("inspect"), runtime);
  assertEquals(expired.status, "expired");
  assertEquals(expired.configurationPresent, true);
  await assertRejects(() =>
    controlAudioComparison(request("activate"), runtime)
  );
  assertEquals(state.sets.length, 1);
  const old = config({
    planSha256: "c".repeat(64),
    backendBundleSha256: "d".repeat(64),
  });
  state.digest = await sha256Hex(JSON.stringify(comparisonConfiguration(old)));
  const result = await controlAudioComparison({
    ...request("deactivate", old),
    deployedSha: undefined,
  }, runtime);
  assertEquals(result.cleanup, "verified_absent");
});

Deno.test("comparison activation rejects invalid identity, window and deployment inputs before mutation", async () => {
  const invalid = [
    "",
    "[]",
    "null",
    "{" + "x".repeat(1024),
    config({ extra: true }),
    config({ ownerId: "wrong" }),
    config({ version: 2 }),
    config({ planSha256: "a".repeat(64) }),
    config({ backendBundleSha256: "b".repeat(64) }),
    config({ startsAt: "2026-09-23T22:00:01.000Z" }),
    config({ expiresAt: "2026-09-23T22:00:00.000Z" }),
    config({ expiresAt: "2026-09-24T00:00:00.001Z" }),
    config({ startsAt: "2026-09-23T22:00:00Z" }),
    config({ startsAt: "2026-09-32T22:00:00.000Z" }),
  ];
  for (const raw of invalid) {
    const { state, runtime } = fake();
    await assertRejects(() =>
      controlAudioComparison(request("activate", raw), runtime)
    );
    assertEquals(state.sets.length + state.unsets, 0);
  }
  const { state, runtime } = fake();
  await assertRejects(() =>
    controlAudioComparison({
      ...request("activate"),
      deployedSha: undefined,
    }, runtime)
  );
  assertEquals(state.sets.length, 0);
  state.now = Date.parse("2026-10-22T00:00:00.000Z");
  await assertRejects(() =>
    controlAudioComparison(
      request(
        "activate",
        config({
          startsAt: "2026-10-22T00:00:00.000Z",
          expiresAt: "2026-10-22T01:00:00.000Z",
        }),
      ),
      runtime,
    )
  );
  assertEquals(state.sets.length, 0);
});

Deno.test("comparison control preserves an unrelated replacement for every operation", async () => {
  for (const operation of ["inspect", "activate", "deactivate"] as const) {
    const { state, runtime } = fake();
    state.digest = "f".repeat(64);
    const error = await assertRejects(
      () => controlAudioComparison(request(operation), runtime),
      ComparisonControlError,
    );
    assertEquals(error.evidence.status, "configuration_mismatch");
    assertEquals(state.digest, "f".repeat(64));
    assertEquals(state.sets.length + state.unsets, 0);
  }
});

Deno.test("ambiguous activation errors remove only the intended configuration and redact upstream errors", async () => {
  const { state, runtime } = fake();
  const set = runtime.set;
  runtime.set = async (input) => {
    await set(input);
    throw new Error(config());
  };
  const error = await assertRejects(
    () => controlAudioComparison(request("activate"), runtime),
    ComparisonControlError,
  );
  assertEquals(error.evidence.status, "activation_failed");
  assertEquals(error.evidence.cleanup, "verified_absent");
  assertEquals(state.digest, null);
  assertEquals(state.unsets, 1);
  assert(!JSON.stringify(error.evidence).includes(OWNER));
  assert(!error.message.includes(OWNER));
});

Deno.test("activation cleanup preserves a replacement and reports an unavailable cleanup honestly", async () => {
  for (const unavailable of [false, true]) {
    const { state, runtime } = fake();
    runtime.set = () => {
      state.digest = "f".repeat(64);
      if (unavailable) runtime.list = () => Promise.reject(new Error(config()));
      return Promise.reject(new Error(config()));
    };
    const error = await assertRejects(
      () => controlAudioComparison(request("activate"), runtime),
      ComparisonControlError,
    );
    assertEquals(
      error.evidence.cleanup,
      unavailable ? "unverified" : "replacement_preserved",
    );
    assertEquals(state.unsets, 0);
  }
});

Deno.test("late activation and failed deletion cannot report verified success", async () => {
  const { state, runtime } = fake();
  const set = runtime.set;
  runtime.set = async (input) => {
    await set(input);
    state.now += 7_200_000;
  };
  const late = await assertRejects(
    () => controlAudioComparison(request("activate"), runtime),
    ComparisonControlError,
  );
  assertEquals(late.evidence.cleanup, "verified_absent");
  state.digest = await sha256Hex(
    JSON.stringify(comparisonConfiguration(config())),
  );
  runtime.unset = () => Promise.resolve();
  const failed = await assertRejects(
    () => controlAudioComparison(request("deactivate"), runtime),
    ComparisonControlError,
  );
  assertEquals(failed.evidence.status, "deactivation_unverified");
  assertEquals(failed.evidence.cleanup, "unverified");
});

Deno.test("malformed remote digest inventory fails closed", async () => {
  for (
    const rows of [null, {}, [{ name: COMPARISON_SECRET, value: "bad" }], [
      { name: COMPARISON_SECRET, value: "a".repeat(64) },
      { name: COMPARISON_SECRET, value: "a".repeat(64) },
    ]]
  ) {
    const { state, runtime } = fake();
    runtime.list = () => Promise.resolve(rows);
    await assertRejects(() =>
      controlAudioComparison(request("activate"), runtime)
    );
    assertEquals(state.sets.length + state.unsets, 0);
  }
});

Deno.test("control output remains compatible with runtime owner and expiry enforcement", async () => {
  const { state, runtime } = fake();
  await controlAudioComparison(request("activate"), runtime);
  const configuration = state.sets[0].slice(
    `${COMPARISON_SECRET}='`.length,
    -2,
  );
  const scanId = await audioComparisonScanId(1);
  const body = {
    user_id: OWNER,
    client_scan_id: scanId,
    geoprivacy: "private",
    mimeType: "image/webp",
    deviceLocale: "en",
    deviceTimeZone: "UTC",
    currentMonth: 1,
    timeOfDay: "12:00 PM",
    audioBase64s: ["AA=="],
    audioMediaItems: [{ kind: "audio", sourceIndex: 0 }],
    ownerMediaTimeline: [{ kind: "audio", sourceIndex: 0, audioInputIndex: 0 }],
    audio_comparison: { planSha256: AUDIO_COMPARISON_PLAN_SHA256, slot: 1 },
  };
  assert(
    (await resolveAudioComparison({
      body,
      scanId,
      userId: OWNER,
      configuration,
      now: NOW,
    })) !== null,
  );
  await assertRejects(() =>
    resolveAudioComparison({
      body,
      scanId,
      userId: "22222222-2222-4222-8222-222222222222",
      configuration,
      now: NOW,
    })
  );
  await assertRejects(() =>
    resolveAudioComparison({
      body,
      scanId,
      userId: OWNER,
      configuration,
      now: NOW + 7_200_000,
    })
  );
});

Deno.test("comparison control CLI rejects local, fork, branch and other workflow contexts", () => {
  const env = {
    GITHUB_ACTIONS: "true",
    GITHUB_REPOSITORY: "emreerdener/merian",
    GITHUB_REF: "refs/heads/main",
    GITHUB_EVENT_NAME: "workflow_dispatch",
    GITHUB_WORKFLOW_REF:
      "emreerdener/merian/.github/workflows/identification-audio-comparison.yml@refs/heads/main",
    GITHUB_SHA: SOURCE,
  };
  requireComparisonWorkflow(env);
  for (const key of Object.keys(env)) {
    assertThrows(() => requireComparisonWorkflow({ ...env, [key]: "invalid" }));
  }
});

Deno.test("comparison workflow keeps private input and recovery behind the reviewed Production control", async () => {
  const text = await Deno.readTextFile(
    ".github/workflows/identification-audio-comparison.yml",
  );
  assert(text.includes("default: inspect"));
  assert(text.includes("options: [inspect, activate, deactivate]"));
  assert(text.includes("environment: Production"));
  assert(text.includes("group: supabase-production-deploy"));
  assert(text.includes("cancel-in-progress: false"));
  assert(text.includes("needs.candidate-validation.result == 'success'"));
  assert(text.includes("--mode automatic-release"));
  assert(text.includes("resolve_deployed_health_monitor_modes.ts"));
  assert(text.includes("git diff --exit-code"));
  assert(text.includes("comparison/plan.ts"));
  assert(text.includes("deploymentIdentity.ts"));
  assert(text.includes("--allow-run=supabase"));
  assert(text.includes("require_supabase_cli_version.sh"));
  assert(
    text.includes(
      "IDENTIFICATION_AUDIO_COMPARISON_V1: ${{ secrets.IDENTIFICATION_AUDIO_COMPARISON_V1 }}",
    ),
  );
  assert(!text.includes("inputs.owner"));
  assert(!text.includes("inputs.configuration"));
  assert(!text.includes("schedule:"));
  assert(!text.includes("functions deploy"));
  assert(!text.includes("db push"));
});
