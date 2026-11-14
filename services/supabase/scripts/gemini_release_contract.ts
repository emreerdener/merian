import {
  GEMINI_CANDIDATE_PROFILES,
  GEMINI_EVALUATION_DESCRIPTOR,
  GEMINI_PROFILE_VERSION,
} from "../functions/_shared/ai/geminiProfiles.ts";
import {
  geminiSmokeCatalog,
  geminiSmokeDigest,
} from "../functions/_shared/ai/geminiSmokeCatalog.ts";
import { computeGeminiBundleDigests } from "./generate_gemini_deployment_identity.ts";
export const GEMINI_RELEASE_GATES = Object.freeze({
  candidate_validation: true,
  exact_source: true,
  migrations: true,
  privileged_routines: true,
  function_deployment: true,
  authorization_smokes: true,
  independent_holds: true,
});
export interface GeminiReleaseConfiguration {
  profile_version: string;
  profiles: typeof GEMINI_CANDIDATE_PROFILES;
  evaluation: typeof GEMINI_EVALUATION_DESCRIPTOR;
  aliases: Record<string, string[]>;
  tariffs: string;
  assignments: unknown;
  required_functions: Record<string, string>;
  required_gates: typeof GEMINI_RELEASE_GATES;
  smoke_cases: {
    id: string;
    digest: string;
    model: string;
    reservation_microusd: number;
  }[];
}
export interface GeminiReleaseManifest {
  version: 1;
  release_id: string;
  target: string;
  backend_sha: string;
  configuration_digest: string;
  configuration_text: string;
  app: {
    version: string;
    build: string;
    source_fingerprint: string;
    testflight_group: string;
    availability_checked_at: string;
  };
  authorization: {
    reference: string;
    backend_deployment: true;
    activation: true;
    provider_smokes: true;
    protective_suspension: true;
    spending_cap_microusd: number;
  };
  expected_previous_revision: number;
  window_start: string;
  window_end: string;
}
function object(v: unknown, keys: string[]): Record<string, unknown> {
  if (
    !v || typeof v !== "object" || Array.isArray(v) ||
    Object.keys(v).sort().join() !== keys.sort().join()
  ) throw new Error("gemini_release_shape_invalid");
  return v as Record<string, unknown>;
}
export function parseGeminiReleaseManifest(raw: string): GeminiReleaseManifest {
  if (new TextEncoder().encode(raw).length > 65536) {
    throw new Error("gemini_release_too_large");
  }
  const m = object(JSON.parse(raw), [
    "version",
    "release_id",
    "target",
    "backend_sha",
    "configuration_digest",
    "configuration_text",
    "app",
    "authorization",
    "expected_previous_revision",
    "window_start",
    "window_end",
  ]);
  const app = object(m.app, [
    "version",
    "build",
    "source_fingerprint",
    "testflight_group",
    "availability_checked_at",
  ]);
  const auth = object(m.authorization, [
    "reference",
    "backend_deployment",
    "activation",
    "provider_smokes",
    "protective_suspension",
    "spending_cap_microusd",
  ]);
  const string = (v: unknown, p: RegExp) => typeof v === "string" && p.test(v);
  const date = (v: unknown) =>
    typeof v === "string" &&
    /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(v) &&
    Number.isFinite(Date.parse(v));
  if (
    m.version !== 1 ||
    !string(
      m.release_id,
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/,
    ) ||
    !string(m.target, /^[a-z]{20}$/) ||
    !string(m.backend_sha, /^(?!0{40}$)[0-9a-f]{40}$/) ||
    !string(m.configuration_digest, /^[0-9a-f]{64}$/) ||
    typeof m.configuration_text !== "string" ||
    !Number.isSafeInteger(m.expected_previous_revision) ||
    Number(m.expected_previous_revision) < 0 || !date(m.window_start) ||
    !date(m.window_end) ||
    Date.parse(String(m.window_end)) <= Date.parse(String(m.window_start)) ||
    Date.parse(String(m.window_end)) - Date.parse(String(m.window_start)) >
      86400000 ||
    !string(app.version, /^[0-9]+(?:\.[0-9]+){1,2}$/) ||
    !string(app.build, /^[0-9]{1,12}$/) ||
    !string(app.source_fingerprint, /^[0-9a-f]{64}$/) ||
    !string(app.testflight_group, /^[^\r\n]{1,128}$/) ||
    !date(app.availability_checked_at) ||
    !string(auth.reference, /^[^\r\n]{1,256}$/) ||
    [
      auth.backend_deployment,
      auth.activation,
      auth.provider_smokes,
      auth.protective_suspension,
    ].some((v) => v !== true) ||
    !Number.isSafeInteger(auth.spending_cap_microusd) ||
    Number(auth.spending_cap_microusd) <= 0
  ) throw new Error("gemini_release_manifest_invalid");
  return m as unknown as GeminiReleaseManifest;
}
export async function buildGeminiReleaseConfiguration(
  assignments: unknown,
): Promise<GeminiReleaseConfiguration> {
  const catalog = await geminiSmokeCatalog();
  return {
    profile_version: GEMINI_PROFILE_VERSION,
    profiles: GEMINI_CANDIDATE_PROFILES,
    evaluation: GEMINI_EVALUATION_DESCRIPTOR,
    aliases: {
      "gemini-2.5-flash": ["gemini-2.5-flash"],
      "gemini-2.5-pro": ["gemini-2.5-pro"],
      "gemini-3.8-flash": ["gemini-3.8-flash"],
      "gemini-3.5-flash-lite": ["gemini-3.5-flash-lite"],
    },
    tariffs: "google-standard-2026-11-14+2027-01-01",
    assignments,
    required_functions: await computeGeminiBundleDigests(),
    required_gates: GEMINI_RELEASE_GATES,
    smoke_cases: [...catalog.values()].map((c) => ({
      id: c.id,
      digest: c.digest,
      model: c.model,
      reservation_microusd: c.reservationMicrousd,
    })),
  };
}
export async function verifyGeminiReleaseSource(
  m: GeminiReleaseManifest,
): Promise<GeminiReleaseConfiguration> {
  const c = JSON.parse(m.configuration_text) as GeminiReleaseConfiguration;
  const expected = await buildGeminiReleaseConfiguration(c.assignments);
  if (
    JSON.stringify(expected) !== m.configuration_text ||
    await geminiSmokeDigest(expected) !== m.configuration_digest
  ) throw new Error("gemini_release_source_mismatch");
  if (
    c.smoke_cases.reduce((n, c) => n + c.reservation_microusd, 0) >
      m.authorization.spending_cap_microusd
  ) throw new Error("gemini_release_budget_insufficient");
  return expected;
}
