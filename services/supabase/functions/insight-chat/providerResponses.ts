import {
  extractFieldChatReplyJson,
  fieldChatResponseObject,
} from "../_shared/fieldChat/reply.ts";
import {
  PROMPT_CATEGORY_ALLOWLIST,
  sanitizePromptSuggestions,
} from "./promptSuggestions.ts";
import { sanitizeFieldNotesDraft } from "./prompt.ts";

export function parseFieldNotesResponse(text: string) {
  const row = fieldChatResponseObject(extractFieldChatReplyJson(text), [
    "summary_text",
  ]);
  if (
    typeof row.summary_text !== "string" || !row.summary_text.trim() ||
    row.summary_text.trim().length > 4000
  ) {
    throw new Error("field_notes_response_invalid");
  }
  return sanitizeFieldNotesDraft(row.summary_text.trim());
}
export function parsePromptSuggestionsResponse(text: string) {
  const row = fieldChatResponseObject(extractFieldChatReplyJson(text), [
    "prompts",
  ]);
  if (!Array.isArray(row.prompts) || row.prompts.length > 3) {
    throw new Error("field_chat_prompts_invalid");
  }
  for (const value of row.prompts) {
    const prompt = fieldChatResponseObject(value, ["text", "category"]);
    if (
      typeof prompt.text !== "string" || !prompt.text.trim() ||
      prompt.text.trim().replace(/\s+/g, " ").length > 120 ||
      typeof prompt.category !== "string" ||
      !PROMPT_CATEGORY_ALLOWLIST.has(prompt.category)
    ) {
      throw new Error("field_chat_prompts_invalid");
    }
  }
  // Existing safety filtering and deduplication follow strict schema validation.
  return sanitizePromptSuggestions(row.prompts);
}
