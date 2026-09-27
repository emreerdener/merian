import {
  AUDIO_PROMPT_COMPARISON_PLAN,
  AUDIO_PROMPT_COMPARISON_PLAN_SHA256,
} from "../functions/identify-multimodal/comparison/promptPlan.ts";
import { IDENTIFICATION_BUNDLE_SHA256 } from "../functions/identify-multimodal/deploymentIdentity.ts";
import { listedSecretDigest, sha256Hex } from "./verify_edge_secret_digest.ts";

export const PROMPT_COMPARISON_PROJECT = "qlarqavoqhkuwzmevrmf";
export const PROMPT_COMPARISON_SECRET =
  "IDENTIFICATION_AUDIO_PROMPT_COMPARISON_V1";
const SHA = /^[a-f0-9]{64}$/;
const REVISION = /^[a-f0-9]{40}$/;
const UUID =
  /^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const RETENTION_START = Date.parse(
  AUDIO_PROMPT_COMPARISON_PLAN.startsNotBefore,
);
const RETENTION_END = Date.parse(AUDIO_PROMPT_COMPARISON_PLAN.expiresNotAfter);
export type PromptComparisonOperation = "inspect" | "activate" | "deactivate";
type ControlStage =
  | "initial_inventory"
  | "configuration_validation"
  | "activation_validation"
  | "set"
  | "verify_set"
  | "verify_window"
  | "unset"
  | "verify_unset";
type CliFailureKind =
  | "nonzero_exit"
  | "timeout"
  | "spawn_failure"
  | "io_failure"
  | "output_limit"
  | "env_file_unreadable"
  | "env_file_invalid"
  | "project_config_invalid"
  | "empty_input"
  | "remote_rejected"
  | "transport_failure"
  | "authentication_failure";

/** Match only fixed CLI codes. Never return its message, detail or unknown code. */
export function promptComparisonCliFailure(stdout: Uint8Array): CliFailureKind {
  if (stdout.length > 1_048_576) return "output_limit";
  try {
    const result = JSON.parse(new TextDecoder().decode(stdout));
    if (
      !result || typeof result !== "object" || Array.isArray(result) ||
      result._tag !== "Error" || !result.error ||
      typeof result.error !== "object" || Array.isArray(result.error) ||
      typeof result.error.code !== "string"
    ) return "nonzero_exit";
    switch (result.error?.code) {
      case "LegacySecretsEnvFileOpenError":
        return "env_file_unreadable";
      case "LegacySecretsEnvFileParseError":
        return "env_file_invalid";
      case "LegacySecretsConfigParseError":
        return "project_config_invalid";
      case "LegacySecretsNoArgumentsError":
        return "empty_input";
      case "LegacySecretsSetUnexpectedStatusError":
      case "LegacySecretsListUnexpectedStatusError":
      case "LegacySecretsUnsetUnexpectedStatusError":
        return "remote_rejected";
      case "LegacySecretsSetNetworkError":
      case "LegacySecretsListNetworkError":
      case "LegacySecretsUnsetNetworkError":
        return "transport_failure";
      case "LegacyPlatformAuthRequiredError":
      case "LegacyInvalidAccessTokenError":
        return "authentication_failure";
    }
  } catch { /* Unknown output remains unclassified and is never retained. */ }
  return "nonzero_exit";
}

/** Only locally defined categories may cross the private subprocess boundary. */
export class PromptComparisonCliError extends Error {
  constructor(readonly kind: CliFailureKind) {
    super(kind);
  }
}

interface Configuration {
  version: 1;
  block: 1 | 2 | 3;
  ownerId: string;
  planSha256: string;
  backendBundleSha256: string;
  startsAt: string;
  expiresAt: string;
}

export interface PromptComparisonControlRuntime {
  now(): number;
  list(): Promise<unknown>;
  set(canonicalConfiguration: string): Promise<void>;
  unset(): Promise<void>;
}

export interface PromptComparisonControlEvidence {
  version: "audio_prompt_comparison_control_v1";
  operation: PromptComparisonOperation;
  target: typeof PROMPT_COMPARISON_PROJECT;
  sourceSha: string;
  deployedSha: string | null;
  observedAt: string;
  status: string;
  mutationAttempted: boolean;
  cleanup:
    | "not_needed"
    | "verified_absent"
    | "replacement_preserved"
    | "unverified";
  configurationPresent: boolean | null;
  block: 1 | 2 | 3 | null;
  window: { startsAt: string; expiresAt: string } | null;
  planSha256: string | null;
  backendBundleSha256: string | null;
  automaticIdentificationRequests: 0;
  failure: { stage: ControlStage; kind: CliFailureKind | "validation" } | null;
}

export class PromptComparisonControlError extends Error {
  constructor(readonly evidence: PromptComparisonControlEvidence) {
    // Never forward a CLI/API/parser error or the private configuration.
    super(evidence.status);
  }
}

function require(condition: unknown): asserts condition {
  if (!condition) throw new Error("invalid_comparison_control_input");
}

function instant(value: unknown): string {
  require(typeof value === "string");
  require(/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value));
  const time = Date.parse(value);
  require(Number.isFinite(time) && new Date(time).toISOString() === value);
  return value;
}

/** Fixed-key canonicalization keeps private JSON out of arguments and files. */
export function promptComparisonConfiguration(raw: string): Configuration {
  require(new TextEncoder().encode(raw).length <= 1024);
  const value = JSON.parse(raw);
  require(value && typeof value === "object" && !Array.isArray(value));
  require(
    Object.keys(value).sort().join(",") ===
      "backendBundleSha256,block,expiresAt,ownerId,planSha256,startsAt,version",
  );
  require(
    value.version === 1 && typeof value.ownerId === "string" &&
      UUID.test(value.ownerId),
  );
  require(typeof value.block === "number" && [1, 2, 3].includes(value.block));
  require(typeof value.planSha256 === "string" && SHA.test(value.planSha256));
  require(
    typeof value.backendBundleSha256 === "string" &&
      SHA.test(value.backendBundleSha256),
  );
  const startsAt = instant(value.startsAt),
    expiresAt = instant(value.expiresAt);
  const duration = Date.parse(expiresAt) - Date.parse(startsAt);
  // Cleanup also accepts an older, expired server-valid configuration. It must
  // not depend on the current plan/bundle or on a fresh deployment succeeding.
  require(duration > 0 && duration <= 7_200_000);
  return {
    version: 1,
    block: value.block,
    ownerId: value.ownerId,
    planSha256: value.planSha256,
    backendBundleSha256: value.backendBundleSha256,
    startsAt,
    expiresAt,
  };
}

function remoteDigest(payload: unknown): string | null {
  require(Array.isArray(payload));
  if (!payload.some((entry) => entry?.name === PROMPT_COMPARISON_SECRET)) {
    return null;
  }
  return listedSecretDigest(payload, PROMPT_COMPARISON_SECRET);
}

export async function controlAudioPromptComparison(
  request: {
    operation: PromptComparisonOperation;
    sourceSha: string;
    deployedSha?: string;
    privateConfiguration: string;
  },
  runtime: PromptComparisonControlRuntime,
): Promise<PromptComparisonControlEvidence> {
  require(["inspect", "activate", "deactivate"].includes(request.operation));
  require(REVISION.test(request.sourceSha));
  require(!request.deployedSha || REVISION.test(request.deployedSha));
  const evidence: PromptComparisonControlEvidence = {
    version: "audio_prompt_comparison_control_v1",
    operation: request.operation,
    target: PROMPT_COMPARISON_PROJECT,
    sourceSha: request.sourceSha,
    deployedSha: request.deployedSha ?? null,
    observedAt: new Date(runtime.now()).toISOString(),
    status: "preflight_failed",
    mutationAttempted: false,
    cleanup: "not_needed",
    configurationPresent: null,
    block: null,
    window: null,
    planSha256: null,
    backendBundleSha256: null,
    automaticIdentificationRequests: 0,
    failure: null,
  };
  let intendedDigest: string | undefined;
  let settingAttempted = false;
  let stage: ControlStage = "initial_inventory";
  try {
    const before = remoteDigest(await runtime.list());
    evidence.configurationPresent = before !== null;
    if (request.operation !== "activate" && before === null) {
      return { ...evidence, status: "disabled", cleanup: "verified_absent" };
    }
    stage = "configuration_validation";
    const config = promptComparisonConfiguration(request.privateConfiguration);
    const canonical = JSON.stringify(config);
    intendedDigest = await sha256Hex(canonical);
    evidence.block = config.block;
    evidence.window = {
      startsAt: config.startsAt,
      expiresAt: config.expiresAt,
    };
    evidence.planSha256 = config.planSha256;
    evidence.backendBundleSha256 = config.backendBundleSha256;
    if (before !== null && before !== intendedDigest) {
      evidence.status = "configuration_mismatch";
      throw new PromptComparisonControlError(evidence);
    }
    if (request.operation === "deactivate") {
      evidence.mutationAttempted = true;
      stage = "unset";
      await runtime.unset();
      stage = "verify_unset";
      require(remoteDigest(await runtime.list()) === null);
      return {
        ...evidence,
        status: "disabled",
        configurationPresent: false,
        cleanup: "verified_absent",
      };
    }
    const start = Date.parse(config.startsAt),
      end = Date.parse(config.expiresAt);
    const now = runtime.now();
    const reviewed =
      config.planSha256 === AUDIO_PROMPT_COMPARISON_PLAN_SHA256 &&
      config.backendBundleSha256 === IDENTIFICATION_BUNDLE_SHA256 &&
      start >= RETENTION_START && end <= RETENTION_END;
    const state = now < start ? "scheduled" : now >= end ? "expired" : "active";
    if (request.operation === "inspect") {
      return { ...evidence, status: reviewed ? state : "incompatible" };
    }
    // The workflow proves candidate readiness and deployed source identity
    // before supplying deployedSha. The control cannot widen the reviewed plan.
    stage = "activation_validation";
    require(request.deployedSha && reviewed && state === "active");
    require(end - start <= 7_200_000);
    if (before === intendedDigest) {
      return { ...evidence, status: "already_active" };
    }
    evidence.mutationAttempted = true;
    settingAttempted = true;
    stage = "set";
    await runtime.set(canonical);
    stage = "verify_set";
    require(remoteDigest(await runtime.list()) === intendedDigest);
    // A delayed API call must not produce a false successful activation.
    stage = "verify_window";
    require(runtime.now() < end);
    return { ...evidence, status: "active", configurationPresent: true };
  } catch (error) {
    evidence.failure = {
      stage,
      kind: error instanceof PromptComparisonCliError
        ? error.kind
        : "validation",
    };
    if (settingAttempted) {
      evidence.status = "activation_failed";
      evidence.cleanup = "unverified";
      try {
        const actual = remoteDigest(await runtime.list());
        if (actual === intendedDigest) {
          await runtime.unset();
          require(remoteDigest(await runtime.list()) === null);
          evidence.configurationPresent = false;
          evidence.cleanup = "verified_absent";
        } else if (actual === null) {
          evidence.configurationPresent = false;
          evidence.cleanup = "verified_absent";
        } else {
          evidence.configurationPresent = true;
          evidence.cleanup = "replacement_preserved";
        }
      } catch {
        /* Evidence retains unverified; no private error text escapes. */
      }
    } else if (error instanceof PromptComparisonControlError) {
      throw error;
    } else if (evidence.mutationAttempted) {
      evidence.status = "deactivation_unverified";
      evidence.configurationPresent = null;
      evidence.cleanup = "unverified";
    }
    throw new PromptComparisonControlError(evidence);
  }
}

export function requirePromptComparisonWorkflow(
  env: Record<string, string>,
): void {
  require(env.GITHUB_ACTIONS === "true");
  require(env.GITHUB_REPOSITORY === "emreerdener/merian");
  require(env.GITHUB_REF === "refs/heads/main");
  require(env.GITHUB_EVENT_NAME === "workflow_dispatch");
  require(
    env.GITHUB_WORKFLOW_REF ===
      "emreerdener/merian/.github/workflows/identification-audio-prompt-comparison.yml@refs/heads/main",
  );
  require(REVISION.test(env.GITHUB_SHA));
}

export async function runAudioPromptComparisonControl(): Promise<void> {
  const env = Object.fromEntries([
    "GITHUB_ACTIONS",
    "GITHUB_REPOSITORY",
    "GITHUB_REF",
    "GITHUB_EVENT_NAME",
    "GITHUB_WORKFLOW_REF",
    "GITHUB_SHA",
  ].map((name) => [name, Deno.env.get(name) ?? ""]));
  requirePromptComparisonWorkflow(env);
  const options = new Map<string, string>();
  for (let i = 0; i < Deno.args.length; i += 2) {
    const key = Deno.args[i], value = Deno.args[i + 1];
    require(["--operation", "--deployed-sha", "--evidence"].includes(key));
    require(value && !options.has(key));
    options.set(key, value);
  }
  const operation = options.get("--operation") as PromptComparisonOperation;
  const output = options.get("--evidence");
  require(output);
  const accessToken = Deno.env.get("SUPABASE_ACCESS_TOKEN") ?? "";
  require(accessToken.length > 0);
  // A new, private output contains only the whitelisted evidence projection.
  const file = await Deno.open(output, {
    createNew: true,
    write: true,
    mode: 0o600,
  });
  const cli = async (
    args: string[],
    configuration?: string,
  ): Promise<string> => {
    const signal = AbortSignal.timeout(60_000);
    let child: Deno.ChildProcess;
    try {
      child = new Deno.Command("supabase", {
        args: [
          "secrets",
          ...args,
          "--output-format",
          "json",
          "--project-ref",
          PROMPT_COMPARISON_PROJECT,
        ],
        // A dedicated public template loads exactly one env-backed secret.
        // Do not load the application's config or pass private JSON in argv/files.
        cwd: new URL("./audio-prompt-comparison-control/", import.meta.url),
        clearEnv: true,
        env: {
          PATH: Deno.env.get("PATH") ?? "",
          SUPABASE_ACCESS_TOKEN: accessToken,
          SUPABASE_TELEMETRY_DISABLED: "1",
          ...(configuration === undefined
            ? {}
            : { MERIAN_AUDIO_PROMPT_COMPARISON_VALUE: configuration }),
        },
        stdin: "null",
        stdout: "piped",
        // Upstream errors can contain the private value; discard them entirely.
        stderr: "null",
        signal,
      }).spawn();
    } catch {
      throw new PromptComparisonCliError("spawn_failure");
    }
    try {
      const result = await child.output();
      if (signal.aborted) throw new PromptComparisonCliError("timeout");
      if (!result.success) {
        throw new PromptComparisonCliError(
          promptComparisonCliFailure(result.stdout),
        );
      }
      // Validate the buffered result; this is not a streaming memory bound.
      if (result.stdout.length > 1_048_576) {
        throw new PromptComparisonCliError("output_limit");
      }
      return new TextDecoder().decode(result.stdout);
    } catch (error) {
      if (error instanceof PromptComparisonCliError) throw error;
      throw new PromptComparisonCliError(
        signal.aborted ? "timeout" : "io_failure",
      );
    } finally {
      try {
        child.kill("SIGKILL");
      } catch { /* Already stopped. */ }
      await child.status;
    }
  };
  let result: PromptComparisonControlEvidence;
  let failed = false;
  try {
    try {
      result = await controlAudioPromptComparison({
        operation,
        sourceSha: env.GITHUB_SHA,
        deployedSha: options.get("--deployed-sha"),
        privateConfiguration: Deno.env.get(PROMPT_COMPARISON_SECRET) ?? "",
      }, {
        now: Date.now,
        list: async () => JSON.parse(await cli(["list", "--output", "json"])),
        set: async (configuration) => {
          await cli(["set"], configuration);
        },
        unset: async () => {
          await cli(["unset", PROMPT_COMPARISON_SECRET, "--yes"]);
        },
      });
    } catch (error) {
      if (!(error instanceof PromptComparisonControlError)) throw error;
      result = error.evidence;
      failed = true;
    }
    const bytes = new TextEncoder().encode(
      JSON.stringify(result, null, 2) + "\n",
    );
    let written = 0;
    while (written < bytes.length) {
      written += await file.write(bytes.subarray(written));
    }
    await file.sync();
    console.log(JSON.stringify(result));
  } finally {
    file.close();
  }
  if (failed) Deno.exitCode = 1;
}

if (import.meta.main) {
  try {
    await runAudioPromptComparisonControl();
  } catch {
    console.error(
      "audio_prompt_comparison_control_failed; no private details retained",
    );
    Deno.exitCode = 1;
  }
}
