/**
 * Existing Gemini metric meanings, not calibrated probabilities. SQL NULL is
 * legacy; missing/unknown present metadata is not. Keep parity with
 * internal.identification_metrics_are_gemini_compatible and native bands.
 * This pure predicate never chooses a provider or makes an inference request.
 */
export function identificationMetricsAreGeminiCompatible(
  value: unknown,
  tier: unknown,
): boolean {
  if (value === null) return true;
  if (!isRecord(value) || (tier !== "flash" && tier !== "pro")) return false;
  const pro = tier === "pro";
  const common = {
    version: 1,
    provider: "gemini",
    binding: "gemini_baseline_v1",
    model: pro ? "gemini-2.5-pro" : "gemini-2.5-flash",
    policy_version: 1,
    timeout_ms: 90_000,
  };
  let profile: Record<string, unknown>;
  switch (value.variant) {
    case "audio_compat":
      profile = {
        variant: "audio_compat",
        operation: "scan_audio_identification",
        prompt: "identify_audio_compat_v2",
        schema: "merian_audio_v2",
        confidence: "gemini_audio_compat_v2",
        diagnostic_trigger: null,
        prompt_diagnostic_trigger: null,
        safety: null,
        generation: {
          temperature: 0.1,
          seed: 42,
          top_k: null,
          max_output_tokens: 2048,
          thinking_budget: 2048,
        },
      };
      break;
    case "vision_compat":
      profile = {
        variant: "vision_compat",
        operation: "scan_identification",
        prompt: "identify_vision_v1",
        schema: "merian_identify_v1",
        confidence: "gemini_vision_compat_v1",
        diagnostic_trigger: 0.99,
        prompt_diagnostic_trigger: 0.99,
        safety: "biological_vision_v1",
        generation: {
          temperature: 0.1,
          seed: 42,
          top_k: 40,
          max_output_tokens: pro ? 8192 : 4096,
          thinking_budget: pro ? 5000 : 2048,
        },
      };
      break;
    case "description_compat":
      profile = {
        variant: "description_compat",
        operation: "scan_identification",
        prompt: "identify_describe_v1",
        schema: "merian_describe_v1",
        confidence: "gemini_describe_v1",
        diagnostic_trigger: null,
        prompt_diagnostic_trigger: null,
        safety: null,
        generation: {
          temperature: 0.15,
          seed: 42,
          top_k: 40,
          max_output_tokens: pro ? 4096 : 2048,
          thinking_budget: pro ? 3000 : 1024,
        },
      };
      break;
    case "multimodal": {
      if (typeof value.prompt !== "string") return false;
      const audio = value.prompt === "identify_audio_v2" ||
        (pro && value.prompt === "identify_audio_uncertainty_experiment_v1");
      if (
        !audio &&
        !["identify_vision_v1", "identify_blended_v1", "identify_text_v1"]
          .includes(value.prompt)
      ) return false;
      profile = {
        variant: "multimodal",
        operation: "scan_identification",
        prompt: value.prompt,
        schema: audio ? "merian_audio_v2" : "merian_identify_v1",
        confidence: audio ? "gemini_audio_v2" : "gemini_identify_v1",
        diagnostic_trigger: 0.99,
        prompt_diagnostic_trigger: null,
        safety: null,
        generation: {
          temperature: 0.1,
          seed: 42,
          top_k: null,
          max_output_tokens: 8192,
          thinking_budget: pro ? 5000 : null,
        },
      };
      break;
    }
    default:
      return false;
  }
  return exactRecord(value, { ...common, ...profile });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactRecord(
  value: unknown,
  expected: Record<string, unknown>,
): boolean {
  return isRecord(value) &&
    Object.keys(value).length === Object.keys(expected).length &&
    Object.entries(expected).every(([key, expectedValue]) =>
      Object.hasOwn(value, key) &&
      (isRecord(expectedValue)
        ? exactRecord(value[key], expectedValue)
        : Object.is(value[key], expectedValue))
    );
}
