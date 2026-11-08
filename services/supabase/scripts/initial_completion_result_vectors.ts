/** Synthetic retained-result parity inputs for the next native delivery decoder.
 * Generated only from the frozen private v1 owner, never the live Identify DTO. */
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "../functions/_shared/initialAnalysis/canonical.ts";
import {
  capture,
  data,
  other,
} from "../functions/_shared/initialAnalysis/fixtures/resultEvidence.ts";
import { initialMediaHash } from "../functions/_shared/initialAnalysis/mediaBinding.ts";
import {
  type CapturedInitialResult,
  decodeInitialResult,
  type InitialResultReference,
} from "../functions/_shared/initialAnalysis/resultEvidence.ts";

export interface NativeInitialResultVector {
  name: string;
  valid: boolean;
  reference: InitialResultReference;
  original_provenance: string;
  evidence: CapturedInitialResult;
}
const bytes = new TextEncoder();
const hash = (domain: string, text: string) =>
  initialMediaHash(
    bytes.encode(`merian.initial-analysis.${domain}.v1\n${text}`),
  );

export async function initialCompletionResultVectors() {
  const baseline = await capture();
  const vectors: NativeInitialResultVector[] = [];
  const add = (
    name: string,
    evidence: CapturedInitialResult,
    valid: boolean,
    reference = evidence.reference,
    original = evidence.provenance_canonical,
  ) =>
    vectors.push({
      name,
      valid,
      reference,
      original_provenance: original,
      evidence,
    });
  add("retained_v1", baseline, true);
  for (
    const number of [0, 1, Number.MIN_VALUE, 0.0000001, 0.30000000000000004]
  ) {
    const value = data();
    value.confidence_score = number;
    add(`decimal_${number}`, await capture(value), true);
  }
  const unicode = data();
  unicode.ai_reasoning = "\uFEFFe\u0301 synthetic 🦋";
  add("exact_unicode_bytes", await capture(unicode), true);
  const nullable = data();
  nullable.ecology_type = null;
  add("optional_null_distinct_from_omission", await capture(nullable), true);
  add("changed_expected_invocation", baseline, false, {
    ...baseline.reference,
    invocation_id: other,
  });
  add("changed_original_provenance", baseline, false, baseline.reference, "{}");
  add(
    "wrong_result_digest",
    { ...baseline, result_digest: "0".repeat(64) },
    false,
  );
  add("wrong_provenance_digest", {
    ...baseline,
    provenance_digest: "0".repeat(64),
  }, false);
  add("noncanonical_result", {
    ...baseline,
    result_canonical: `${baseline.result_canonical}\n`,
  }, false);

  async function mutate(
    name: string,
    change: (r: Record<string, unknown>, d: Record<string, unknown>) => void,
  ) {
    const result = parseInitialCanonicalText(
      baseline.result_canonical,
    ) as Record<
      string,
      unknown
    >;
    change(result, result.data as Record<string, unknown>);
    const text = initialCanonicalText(result);
    // Recompute the hash: these cases must fail semantics, not only integrity.
    add(name, {
      ...baseline,
      result_canonical: text,
      result_digest: await hash("result", text),
    }, false);
  }
  await mutate("wrong_embedded_invocation", (r) => r.invocation_id = other);
  await mutate("unknown_data_field", (_, d) => d.unreviewed = true);
  await mutate("missing_required_field", (_, d) => delete d.scan_id);
  await mutate("missing_required_colors", (_, d) => delete d.colors);
  await mutate("wrong_data_scan", (_, d) => d.scan_id = other);
  for (const value of ["-0", "0.870", "1e-7", "0.10000000000000001", "1.1"]) {
    await mutate(
      `invalid_decimal_${value}`,
      (_, d) => d.confidence_score = value,
    );
  }
  await mutate(
    "numeric_instead_of_decimal_string",
    (_, d) => d.confidence_score = 1,
  );
  await mutate(
    "untyped_provenance",
    (_, d) => d.identification_provenance = {},
  );
  await mutate("unknown_usage_field", (r) => {
    (r.provider_usage as Record<string, unknown>).unreviewed = true;
  });
  await mutate("negative_usage", (r) => {
    (r.provider_usage as Record<string, unknown>).input_tokens = -1;
  });
  // Exercise both semantic branches and provider accounting with rehashed
  // synthetic evidence. This is decoder parity, never a provider execution.
  async function semantic(
    name: string,
    valid: boolean,
    change: (r: Record<string, unknown>, d: Record<string, unknown>) => void,
  ) {
    const result = parseInitialCanonicalText(
      baseline.result_canonical,
    ) as Record<string, unknown>;
    const d = result.data as Record<string, unknown>;
    change(result, d);
    const resultText = initialCanonicalText(result);
    const provenance = initialCanonicalText(d.identification_provenance);
    add(name, {
      ...baseline,
      result_canonical: resultText,
      provenance_canonical: provenance,
      result_digest: await hash("result", resultText),
      provenance_digest: await hash("result-provenance", provenance),
    }, valid);
  }
  function primary(d: Record<string, unknown>, resolution: string) {
    (d.identification_provenance as Record<string, unknown>).schema =
      "merian_identify_primary_v1";
    d.candidates = null;
    d.is_new_to_merian_dictionary = false;
    d.is_biological_subject = resolution !== "non_biological";
    if (["unresolved_biological", "non_biological"].includes(resolution)) {
      d.scientific_name = null;
    }
    d.primary_identification = {
      version: 1,
      resolution,
      scientific_name: d.scientific_name,
      common_name: d.common_name,
    };
  }
  for (
    const resolution of [
      "species",
      "genus",
      "family",
      "unresolved_biological",
      "non_biological",
    ]
  ) {
    await semantic(
      `primary_${resolution}`,
      true,
      (_, d) => primary(d, resolution),
    );
  }
  await semantic("primary_mismatched_name", false, (_, d) => {
    primary(d, "species");
    d.common_name = "Different synthetic name";
  });
  await semantic("primary_trimmed_name", false, (_, d) => {
    d.common_name = " Synthetic name";
    primary(d, "species");
  });
  await semantic("primary_non_species_effect", false, (_, d) => {
    primary(d, "family");
    d.is_new_to_merian_dictionary = true;
  });
  function gemini(d: Record<string, unknown>) {
    const p = d.identification_provenance as Record<string, unknown>;
    p.version = 1;
    p.provider = "gemini";
    p.generation = {
      temperature: "0.7",
      seed: null,
      top_k: null,
      max_output_tokens: 1024,
      thinking_budget: null,
    };
  }
  await semantic("gemini_modality_usage", true, (r, d) => {
    gemini(d);
    (r.provider_usage as Record<string, unknown>).modality_breakdown = {
      prompt: { text: 2, image: 3, audio: 4, video: 5 },
      cached: {},
      candidates: { text: 1 },
      tool: {},
    };
  });
  await semantic("gemini_missing_modality_category", false, (_, d) => {
    gemini(d);
  });
  // Assert the fixed owner's verdict before emitting any native test input.
  for (const v of vectors) {
    let accepted = false;
    try {
      await decodeInitialResult(v.evidence, v.reference, v.original_provenance);
      accepted = true;
    } catch { /* explicit rejected vector */ }
    if (accepted !== v.valid) {
      throw new Error(`initial_result_vector_${v.name}`);
    }
  }
  return vectors;
}
