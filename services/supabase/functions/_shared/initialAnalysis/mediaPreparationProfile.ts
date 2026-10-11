/** Dormant metadata codec. Validation never installs or qualifies a profile. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import { validateInitialMediaSourceCandidate } from "./mediaSourceCandidate.ts";
import type { InitialMediaSourcePlan } from "./mediaSourceSemantics.ts";
import schema from "./media-preparation-profile-schema-v1.json" with {
  type: "json",
};

export type InitialSourceRole =
  | "photo"
  | "recording"
  | "video_frame"
  | "video_audio"
  | "raw_video";
export interface PreparationLimits {
  source_bytes: number;
  output_bytes: number;
  cpu_ms: number;
  heap_bytes: number;
  wall_ms: number;
}
export interface InitialPreparationRule {
  role: InitialSourceRole;
  source_types: string[];
  transform: string;
  target_sample_rate: number | null;
  preserve_short_video_context: boolean | null;
  max_count: number;
  limits: PreparationLimits;
}
export interface InitialMediaPreparationProfile {
  version: 1;
  spec: {
    profile_id: string;
    profile_version: number;
    input_profile: string;
    route: string;
    focus_policy: "input_v1_bounds";
    runtime: {
      engine: "deno";
      version: string;
      platform: string;
      abi: string;
      protocol: number;
    };
    artifact: { sha256: string; byte_count: number };
    identities: {
      source: string;
      validator: string;
      transform: string;
      configuration: string;
    };
    rules: InitialPreparationRule[];
    max_sources: number;
    limits: PreparationLimits;
  };
  qualification: {
    spec_digest: string;
    evidence_digest: string;
    harness_digest: string;
    source_revision: string;
  };
}
export async function initialMediaContractDigest(
  domain: "profile_spec" | "profile" | "installation" | "source_plan",
  canonical: string,
): Promise<string> {
  const bytes = new TextEncoder().encode(
    `merian.initial-analysis.media.${domain}.v1\n${canonical}`,
  );
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((
    b,
  ) => b.toString(16).padStart(2, "0")).join("");
}
export function initialSourceRole(
  source: InitialMediaSourcePlan["sources"][number],
): InitialSourceRole {
  if (source.kind === "video") return "raw_video";
  if (source.kind === "audio") {
    return source.clip_index === null ? "recording" : "video_audio";
  }
  return source.clip_index === null ? "photo" : "video_frame";
}
export function initialSourceInputProfile(
  plan: InitialMediaSourcePlan,
): string {
  if (plan.route === "identify") return "vision_compat_v1";
  const audio = plan.sources.some((s) => s.kind === "audio");
  if (plan.capture.has_video) {
    return audio ? "multimodal_video_audio_v1" : "multimodal_video_frames_v1";
  }
  return plan.sources.some((s) => s.kind === "image")
    ? audio ? "multimodal_photo_audio_v1" : "multimodal_photo_v1"
    : "multimodal_audio_v1";
}
const expectedRoles: Record<string, InitialSourceRole[]> = {
  vision_compat_v1: ["photo"],
  multimodal_photo_v1: ["photo"],
  multimodal_audio_v1: ["recording"],
  multimodal_photo_audio_v1: ["photo", "recording"],
  multimodal_video_frames_v1: ["raw_video", "video_frame"],
  multimodal_video_audio_v1: ["raw_video", "video_frame", "video_audio"],
};
export async function validateInitialMediaPreparationProfile(
  value: unknown,
): Promise<string> {
  const text = initialCanonicalText(value),
    frozen = parseInitialCanonicalText(text);
  if (
    new TextEncoder().encode(text).length > 65536 ||
    !matchesInitialSchema(frozen, schema)
  ) return invalidInitialInput();
  const profile = frozen as unknown as InitialMediaPreparationProfile,
    spec = profile.spec;
  const roles = spec.rules.map((r) => r.role);
  if (
    new Set(roles).size !== roles.length ||
    initialCanonicalText([...roles].sort()) !==
      initialCanonicalText([...expectedRoles[spec.input_profile]].sort()) ||
    (spec.route === "identify") !==
      (spec.input_profile === "vision_compat_v1") ||
    profile.qualification.spec_digest !==
      await initialMediaContractDigest(
        "profile_spec",
        initialCanonicalText(spec),
      )
  ) return invalidInitialInput();
  for (const rule of spec.rules) {
    const audio = rule.role === "recording" || rule.role === "video_audio",
      raw = rule.role === "raw_video";
    const allowed = audio
      ? ["audio/wav"]
      : raw
      ? ["video/mp4"]
      : ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"];
    if (
      !rule.source_types.length ||
      new Set(rule.source_types).size !== rule.source_types.length ||
      rule.source_types.some((t) => !allowed.includes(t)) ||
      rule.transform !==
        (audio
          ? "initial_audio_v1"
          : rule.role === "video_frame"
          ? "video_frame_v1"
          : "identity_v1") ||
      (audio
        ? rule.target_sample_rate === null ||
          rule.preserve_short_video_context !== (rule.role === "video_audio")
        : rule.target_sample_rate !== null ||
          rule.preserve_short_video_context !== null) ||
      (raw
        ? rule.limits.output_bytes !== 0 || rule.max_count !== 1
        : rule.limits.output_bytes === 0)
    ) return invalidInitialInput();
  }
  return text;
}
/** Match a complete declared cohort. Actual bytes, eligibility and grants are separate. */
export async function assertInitialMediaProfileMatches(
  candidate: unknown,
  value: unknown,
): Promise<void> {
  const c = JSON.parse(validateInitialMediaSourceCandidate(candidate)) as {
    source_plan: InitialMediaSourcePlan;
  };
  const p = JSON.parse(
    await validateInitialMediaPreparationProfile(value),
  ) as InitialMediaPreparationProfile;
  const plan = c.source_plan, spec = p.spec;
  const unavailable = () => {
    throw new Error("initial_analysis_preparation_unavailable");
  };
  if (
    plan.route !== spec.route ||
    initialSourceInputProfile(plan) !== spec.input_profile ||
    plan.sources.length > spec.max_sources
  ) unavailable();
  const counts = new Map<InitialSourceRole, number>();
  const total: PreparationLimits = {
    source_bytes: 0,
    output_bytes: 0,
    cpu_ms: 0,
    heap_bytes: 0,
    wall_ms: 0,
  };
  for (const source of plan.sources) {
    const role = initialSourceRole(source),
      rule = spec.rules.find((r) => r.role === role);
    if (!rule) return unavailable();
    const count = (counts.get(role) ?? 0) + 1;
    counts.set(role, count);
    if (
      count > rule.max_count ||
      !rule.source_types.includes(source.source_content_type) ||
      source.transform !== rule.transform ||
      (source.transform_parameters?.target_sample_rate ?? null) !==
        rule.target_sample_rate ||
      (source.transform_parameters?.preserve_short_video_context ?? null) !==
        rule.preserve_short_video_context ||
      source.source_byte_count > rule.limits.source_bytes
    ) unavailable();
    total.source_bytes += source.source_byte_count;
    for (
      const key of ["output_bytes", "cpu_ms", "heap_bytes", "wall_ms"] as const
    ) total[key] += rule.limits[key];
  }
  for (const key of Object.keys(total) as (keyof PreparationLimits)[]) {
    if (total[key] > spec.limits[key]) unavailable();
  }
}
