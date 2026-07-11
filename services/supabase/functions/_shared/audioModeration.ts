import { encodeBase64 } from "@std/encoding-base64";
import { readResponseArrayBufferWithinBudget } from "./mediaBudgets.ts";

const AUDIO_MODERATION_MODEL = "gemini-2.5-flash";
const MAX_AUDIO_BYTES = 12 * 1024 * 1024;
const MIN_APPROVAL_CONFIDENCE = 0.85;

const POLICY_CATEGORIES = [
  "sexual_content",
  "child_safety",
  "hate_or_harassment",
  "violence_or_gore",
  "self_harm",
  "dangerous_or_illegal_acts",
  "personal_data",
  "other_harmful_content",
] as const;

type PolicyCategory = typeof POLICY_CATEGORIES[number];

type GeminiAudioClassification = {
  transcript: string;
  non_speech_description: string;
  policy_categories: PolicyCategory[];
  approved: boolean;
  confidence: number;
  requires_review: boolean;
};

export interface AudioModerationDecision {
  approved: boolean;
  model: string;
}

type GeminiGenerate = (
  audioBase64: string,
  mimeType: string,
) => Promise<string>;

async function fetchBoundedAudio(
  url: string,
): Promise<{ bytes: ArrayBuffer; mimeType: string }> {
  let parsedUrl: URL;
  try {
    parsedUrl = new URL(url);
  } catch {
    throw new Error("Audio moderation URL is invalid.");
  }
  if (
    parsedUrl.protocol !== "https:" || parsedUrl.hostname !== "media.merian.app"
  ) {
    throw new Error(
      "Audio moderation URL is not an approved Merian media URL.",
    );
  }
  const response = await fetch(parsedUrl);
  if (!response.ok) {
    throw new Error(`Audio fetch failed with status ${response.status}.`);
  }
  const readResult = await readResponseArrayBufferWithinBudget(
    response,
    MAX_AUDIO_BYTES,
    "Audio exceeds the moderation byte limit.",
  );
  if (
    readResult.error || !readResult.buffer || readResult.buffer.byteLength === 0
  ) {
    throw new Error("Audio is empty or exceeds the moderation byte limit.");
  }
  const responseType = response.headers.get("content-type")?.split(";", 1)[0]
    ?.trim().toLowerCase();
  const mimeType = responseType?.startsWith("audio/")
    ? responseType
    : "audio/wav";
  return { bytes: readResult.buffer, mimeType };
}

const generateGeminiClassification: GeminiGenerate = async (
  audioBase64,
  mimeType,
) => {
  const { _genAI } = await import("./gemini.ts");
  const result = await _genAI.models.generateContent({
    model: AUDIO_MODERATION_MODEL,
    contents: [{
      role: "user",
      parts: [
        {
          text:
            "Classify this complete audio clip for publication in a public community feed. Transcribe all intelligible speech and describe meaningful non-speech sounds. Reject sexual content, child-safety risks, hate or targeted harassment, graphic violence, self-harm promotion, dangerous or illegal instructions, exposed personal data, or other harmful/offensive content. Benign wildlife, environmental sounds, ordinary conversation, and non-harmful music may be approved. If evidence is ambiguous or confidence is low, set requires_review=true and approved=false.",
        },
        { inlineData: { mimeType, data: audioBase64 } },
      ],
    }],
    config: {
      temperature: 0,
      seed: 42,
      maxOutputTokens: 4096,
      thinkingConfig: { thinkingBudget: 0 },
      responseMimeType: "application/json",
      responseSchema: {
        type: "OBJECT",
        properties: {
          transcript: { type: "STRING" },
          non_speech_description: { type: "STRING" },
          policy_categories: {
            type: "ARRAY",
            items: { type: "STRING", enum: [...POLICY_CATEGORIES] },
          },
          approved: { type: "BOOLEAN" },
          confidence: { type: "NUMBER", minimum: 0, maximum: 1 },
          requires_review: { type: "BOOLEAN" },
        },
        required: [
          "transcript",
          "non_speech_description",
          "policy_categories",
          "approved",
          "confidence",
          "requires_review",
        ],
      },
    },
  });
  return result.text ?? "";
};

export function parseGeminiAudioClassification(
  responseText: string,
): GeminiAudioClassification {
  let value: unknown;
  try {
    value = JSON.parse(responseText);
  } catch {
    throw new Error("Gemini audio moderation returned malformed JSON.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Gemini audio moderation returned an invalid response.");
  }
  const row = value as Record<string, unknown>;
  const categories = row.policy_categories;
  if (
    typeof row.transcript !== "string" ||
    typeof row.non_speech_description !== "string" ||
    !Array.isArray(categories) ||
    !categories.every((category) =>
      typeof category === "string" &&
      POLICY_CATEGORIES.includes(category as PolicyCategory)
    ) ||
    typeof row.approved !== "boolean" ||
    typeof row.confidence !== "number" ||
    !Number.isFinite(row.confidence) ||
    row.confidence < 0 || row.confidence > 1 ||
    typeof row.requires_review !== "boolean"
  ) {
    throw new Error("Gemini audio moderation returned an invalid response.");
  }
  if (row.approved && (categories.length > 0 || row.requires_review)) {
    throw new Error(
      "Gemini audio moderation returned an inconsistent decision.",
    );
  }
  return row as GeminiAudioClassification;
}

export async function classifyExploreAudio(
  bytes: ArrayBuffer,
  mimeType: string,
  generate: GeminiGenerate = generateGeminiClassification,
): Promise<AudioModerationDecision> {
  const classification = parseGeminiAudioClassification(
    await generate(encodeBase64(bytes), mimeType),
  );
  return {
    approved: classification.approved &&
      !classification.requires_review &&
      classification.policy_categories.length === 0 &&
      classification.confidence >= MIN_APPROVAL_CONFIDENCE,
    model: AUDIO_MODERATION_MODEL,
  };
}

export async function moderateExploreAudioUrl(
  url: string,
): Promise<AudioModerationDecision> {
  const startedAt = performance.now();
  try {
    if (!Deno.env.get("GEMINI_API_KEY")?.trim()) {
      throw new Error("GEMINI_API_KEY is not configured.");
    }
    const audio = await fetchBoundedAudio(url);
    const decision = await classifyExploreAudio(audio.bytes, audio.mimeType);
    console.log(JSON.stringify({
      event: "explore_audio_moderation_complete",
      approved: decision.approved,
      elapsed_ms: Math.round(performance.now() - startedAt),
      model: decision.model,
    }));
    return decision;
  } catch (error) {
    console.error(JSON.stringify({
      event: "explore_audio_moderation_failed",
      elapsed_ms: Math.round(performance.now() - startedAt),
      error: error instanceof Error ? error.message : String(error),
    }));
    throw error;
  }
}
