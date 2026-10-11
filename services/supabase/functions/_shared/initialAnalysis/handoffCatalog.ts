/** Inactive catalog declarations. No installation or runtime authority. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./handoff-catalog-schema-v1.json" with { type: "json" };
import {
  initialHandoffDigest,
  InitialHandoffProfile,
  validateInitialHandoffProfile,
} from "./handoffProfile.ts";
import {
  initialMediaContractDigest,
  InitialMediaPreparationProfile,
  InitialPreparationRule,
  validateInitialMediaPreparationProfile,
} from "./mediaPreparationProfile.ts";
export function validateInitialHandoffCatalogShape(
  kind: keyof typeof schema,
  value: unknown,
): string {
  const text = initialCanonicalText(value);
  if (
    !Object.hasOwn(schema, kind) ||
    new TextEncoder().encode(text).length > 16384 ||
    !matchesInitialSchema(parseInitialCanonicalText(text), schema[kind])
  ) invalidInitialInput();
  return text;
}
export async function initialHandoffCatalogDigest(
  domain: keyof typeof schema,
  text: string,
): Promise<string> {
  if (domain !== "destination_backend" && domain !== "installation") {
    invalidInitialInput();
  }
  parseInitialCanonicalText(text);
  return [
    ...new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(
          `merian.initial-analysis.handoff.${domain}.v1\n${text}`,
        ),
      ),
    ),
  ].map((x) => x.toString(16).padStart(2, "0")).join("");
}
function unsupported(): never {
  throw new Error("initial_analysis_handoff_catalog_envelope_unsupported");
}
function pairMatches(
  rule: InitialPreparationRule,
  pair: InitialHandoffProfile["cohort_limits"]["content_type_pairs"][number],
): boolean {
  const audio = rule.role === "recording" || rule.role === "video_audio",
    raw = rule.role === "raw_video";
  return pair.kind === (audio ? "audio" : raw ? "video" : "image") &&
    rule.source_types.includes(pair.source_content_type) &&
    (!audio || rule.target_sample_rate === 16000);
}
/** Conservative template: one occurrence of every PROFILE rule at its ceilings.
 * This is not a minimum required runtime cohort (video frames may be absent),
 * a byte-validity witness or qualification of all combinations/multiplicities.
 */
export async function assertInitialHandoffCatalogEnvelope(
  preparation: unknown,
  handoff: unknown,
  protocol: unknown,
): Promise<void> {
  const p = JSON.parse(
    await validateInitialMediaPreparationProfile(preparation),
  ) as InitialMediaPreparationProfile;
  const h = JSON.parse(
    await validateInitialHandoffProfile(handoff, protocol),
  ) as InitialHandoffProfile;
  const rules = p.spec.rules, pairs = h.cohort_limits.content_type_pairs;
  if (
    rules.length > p.spec.max_sources ||
    rules.length > h.cohort_limits.max_ordinals ||
    rules.some((r) => !pairs.some((t) => pairMatches(r, t))) ||
    pairs.some((t) => !rules.some((r) => pairMatches(r, t)))
  ) unsupported();
  let objects = 0, bytes = 0;
  const sums = {
    source_bytes: 0,
    output_bytes: 0,
    cpu_ms: 0,
    heap_bytes: 0,
    wall_ms: 0,
  };
  for (const r of rules) {
    for (const k of Object.keys(sums) as (keyof typeof sums)[]) {
      sums[k] += r.limits[k];
    }
    const audio = r.role === "recording" || r.role === "video_audio",
      raw = r.role === "raw_video";
    objects += audio ? 2 : 1;
    bytes += audio
      ? r.limits.source_bytes + r.limits.output_bytes
      : raw
      ? r.limits.source_bytes
      : Math.max(r.limits.source_bytes, r.limits.output_bytes);
  }
  if (
    Object.values(sums).some((x) => !Number.isSafeInteger(x)) ||
    !Number.isSafeInteger(bytes) ||
    Object.keys(sums).some((k) =>
      sums[k as keyof typeof sums] > p.spec.limits[k as keyof typeof sums]
    ) || objects > h.cohort_limits.max_unique_objects ||
    bytes > h.cohort_limits.max_unique_bytes ||
    45000 + sums.wall_ms + h.total_ms >= 300000
  ) unsupported();
}
export async function validateInitialHandoffInstallation(
  value: unknown,
  handoff: unknown,
  protocol: unknown,
  preparation: unknown,
  destination: unknown,
): Promise<string> {
  const text = validateInitialHandoffCatalogShape("installation", value),
    i = JSON.parse(text);
  const hc = await validateInitialHandoffProfile(handoff, protocol),
    h = JSON.parse(hc) as InitialHandoffProfile;
  const pc = await validateInitialMediaPreparationProfile(preparation);
  const dc = validateInitialHandoffCatalogShape(
      "destination_backend",
      destination,
    ),
    d = JSON.parse(dc);
  if (
    i.profile_generation !== h.generation ||
    i.profile_digest !== await initialHandoffDigest("profile", hc) ||
    i.protocol_artifact_digest !== h.protocol_artifact_digest ||
    i.copy_adapter_digest !== h.copy_adapter_digest ||
    i.verification_adapter_digest !== h.verification_adapter_digest ||
    i.preparation_profile_digest !==
      await initialMediaContractDigest("profile", pc) ||
    i.source_backend_generation !== h.source_backend_generation ||
    i.destination_backend_generation !== h.destination_backend_generation ||
    d.generation !== h.destination_backend_generation ||
    h.destination_backend_config_digest !==
      await initialHandoffCatalogDigest("destination_backend", dc)
  ) invalidInitialInput();
  await assertInitialHandoffCatalogEnvelope(preparation, handoff, protocol);
  return text;
}
