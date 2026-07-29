import type { InsightChatPromptSuggestionPayload } from "./types.ts";
import { isSafetyCriticalQuestion } from "./guards.ts";

export const PROMPT_CATEGORY_ALLOWLIST = new Set([
  "lookalike_compare",
  "hazard",
  "invasive",
  "evidence",
  "habitat",
  "season",
  "confidence",
  "ecology",
  "field_notes",
  "generic",
]);

const PROMPT_ONLY_UNSAFE_PATTERNS = [
  /\b(?:gps|coordinates?|latitude|longitude|exact\s+location|where\s+exactly)\b/i,
  /\b(?:identify|recognize|name|who\s+is)\b.{0,30}\b(?:person|human|face)\b/i,
];

export function isUnsafeFieldChatPromptSuggestion(text: string): boolean {
  return isSafetyCriticalQuestion(text) != null ||
    PROMPT_ONLY_UNSAFE_PATTERNS.some((pattern) => pattern.test(text));
}

export function sanitizePromptSuggestions(
  prompts: unknown,
): InsightChatPromptSuggestionPayload[] {
  if (!Array.isArray(prompts)) return [];

  const seen = new Set<string>();
  const suggestions: InsightChatPromptSuggestionPayload[] = [];

  for (const prompt of prompts) {
    if (!prompt || typeof prompt !== "object") continue;
    const rawText = "text" in prompt ? prompt.text : null;
    const rawCategory = "category" in prompt ? prompt.category : null;
    if (typeof rawText !== "string") continue;

    const text = rawText.trim().replace(/\s+/g, " ");
    if (
      !text || text.length > 120 ||
      isUnsafeFieldChatPromptSuggestion(text)
    ) {
      continue;
    }

    const key = text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);

    const category = typeof rawCategory === "string" &&
        PROMPT_CATEGORY_ALLOWLIST.has(rawCategory)
      ? rawCategory
      : "generic";

    suggestions.push({ text, category });
    if (suggestions.length === 3) break;
  }

  return suggestions;
}
