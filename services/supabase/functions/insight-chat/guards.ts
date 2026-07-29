import { publicHttpError } from "../_shared/http.ts";
import {
  MAX_CHAT_MESSAGE_CHARS,
  MAX_MESSAGES_PER_CONVERSATION,
  MAX_USER_MESSAGE_CHARS,
} from "./types.ts";

export function normalizeAction(
  value: unknown,
):
  | "load"
  | "send"
  | "delete"
  | "feedback"
  | "feature_feedback"
  | "summarize_notes"
  | "suggest_prompts" {
  if (
    value === "load" || value === "send" || value === "delete" ||
    value === "feedback" || value === "feature_feedback" ||
    value === "summarize_notes" || value === "suggest_prompts"
  ) {
    return value;
  }
  throw publicHttpError(
    400,
    "action must be load, send, delete, feedback, feature_feedback, summarize_notes, or suggest_prompts.",
  );
}

export function normalizeFeedbackRating(value: unknown) {
  if (
    value === "helpful" || value === "not_helpful" || value === "wrong" ||
    value === "unsafe" || value === "other"
  ) {
    return value;
  }
  throw publicHttpError(400, "feedback_rating is invalid.");
}

export function normalizeFeatureFeedbackSentiment(value: unknown) {
  if (value == null) return null;
  if (value === "positive" || value === "negative") {
    return value;
  }
  throw publicHttpError(400, "feature_feedback_sentiment is invalid.");
}

export function normalizeFeedbackNote(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw publicHttpError(400, "feedback_note must be a string.");
  }
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (trimmed.length > 1000) {
    throw publicHttpError(
      400,
      "feedback_note must be 1000 characters or fewer.",
    );
  }
  return trimmed;
}

export function normalizeUserMessage(value: unknown): string {
  if (typeof value !== "string") {
    throw publicHttpError(400, "message_text must be a string.");
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw publicHttpError(400, "message_text cannot be empty.");
  }
  if (trimmed.length > MAX_USER_MESSAGE_CHARS) {
    throw publicHttpError(
      400,
      `message_text must be ${MAX_USER_MESSAGE_CHARS} characters or fewer.`,
    );
  }
  return trimmed;
}

export function normalizeAssistantAnswer(
  value: unknown,
  fallback: string,
): string {
  const fallbackText = fallback.trim();
  if (!fallbackText) {
    throw new TypeError("Field Chat answer fallback cannot be empty.");
  }
  const answer = typeof value === "string" && value.trim()
    ? value.trim()
    : fallbackText;
  return Array.from(answer).slice(0, MAX_CHAT_MESSAGE_CHARS).join("");
}

export function assertConversationHasRoom(
  messageCount: number,
  requiredMessageSlots = 2,
): void {
  // A new send needs two rows. An incomplete retry already owns its user row
  // but must still prove that its missing assistant fits inside the same cap.
  if (
    !Number.isSafeInteger(messageCount) ||
    messageCount < 0 ||
    (requiredMessageSlots !== 1 && requiredMessageSlots !== 2) ||
    messageCount + requiredMessageSlots > MAX_MESSAGES_PER_CONVERSATION
  ) {
    throw publicHttpError(
      429,
      "Conversation message limit reached.",
      "conversation_limit_reached",
    );
  }
}

export function isSafetyCriticalQuestion(text: string): string | null {
  const normalized = text.toLowerCase();
  const patterns: Array<[RegExp, string]> = [
    [
      /\b(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:safely\s+)?(?:eat|consume|taste|cook|bake|brew|forage|feed)\b/,
      "foraging_or_ingestion",
    ],
    [
      /\bhow\s+(?:(?:do|can|could|should|would|may)\s+(?:i|we|you)\s+|to\s+)(?:eat|consume|taste|cook|bake|brew|forage|feed)\b/,
      "foraging_or_ingestion",
    ],
    [
      /\b(?:edible|safe\s+to\s+(?:eat|consume|taste|cook|brew|feed)|(?:can|could|should|may|would)\s+(?:this|that|it|these|those)\s+be\s+(?:eaten|consumed|tasted|cooked|brewed|fed)|safe\s+for\s+(?:me|us|people|humans?|children|dogs?|cats?|pets?|livestock))\b/,
      "foraging_or_ingestion",
    ],
    [
      /\b(?:can|could|should|may|would)\s+(?:my|our)\s+(?:dog|cat|pet|livestock)\s+(?:eat|consume|taste)\b/,
      "foraging_or_ingestion",
    ],
    [
      /\b(?:what\s+happens\s+if|after)\s+(?:i|we|you|someone|a\s+person|a\s+child|my\s+(?:dog|cat|pet))\s+(?:eat|ate|consume|consumed|taste|tasted|ingest|ingested)\b/,
      "foraging_or_ingestion",
    ],
    [
      /\b(?:(?:best|safest|proper|recommended)\s+(?:ways?|methods?)\s+to|(?:instructions?|steps?|tips?|advice|guide)\s+(?:for|on|to)|(?:tell|show)\s+me\s+how\s+to)\s+(?:eat(?:ing)?|consum(?:e|ing)|tast(?:e|ing)|cook(?:ing)?|bak(?:e|ing)|brew(?:ing)?|forag(?:e|ing)|feed(?:ing)?)\b/,
      "foraging_or_ingestion",
    ],
    [
      /\b(?:dosage|antidote|treatment\s+(?:advice|instructions?|plan)|medical\s+treatment|veterinary\s+treatment|medicine\s+for|poison\s+control)\b/,
      "medical_or_veterinary",
    ],
    [
      /\b(?:how|what)\s+(?:(?:do|can|could|should|would|may)\s+(?:i|we|you)\s+|to\s+)(?:treat|manage)\b.{0,40}\b(?:rash|bite|sting|venom|allergic\s+reaction|poisoning|exposure)\b/,
      "medical_or_veterinary",
    ],
    [
      /\b(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:treat|medicate|manage)\b.{0,40}\b(?:rash|bite|sting|venom|allergic\s+reaction|poisoning|exposure)\b/,
      "medical_or_veterinary",
    ],
    [
      /\bwhat\s+should\s+(?:i|we|you|someone|a\s+person|a\s+child)\s+do\b.{0,30}\b(?:if|after)\b.{0,30}\b(?:bitten|stung|ate|ingested|rash|allergic\s+reaction|poisoning|exposure)\b/,
      "medical_or_veterinary",
    ],
    [
      /\b(?:i|we|someone|a\s+person|a\s+child|my\s+(?:dog|cat|pet))\b.{0,30}\b(?:was\s+(?:bitten|stung)|ate|ingested|has\s+(?:a\s+)?rash|is\s+having\s+an\s+allergic\s+reaction)\b.{0,40}\b(?:what\s+should|help|emergency|treat|treatment|antidote|dose|dosage)\b/,
      "medical_or_veterinary",
    ],
    [
      /\b(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:safely\s+)?(?:kill|exterminate|trap|capture|handle|pick\s+up|relocate|remove\s+(?:it|this|that|a\s+nest))\b/,
      "dangerous_handling",
    ],
    [
      /\bhow\s+(?:(?:do|can|could|should|would|may)\s+(?:i|we|you)\s+|to\s+)(?:kill|exterminate|trap|capture|handle|pick\s+up|relocate|remove\s+(?:it|this|that|a\s+nest))\b/,
      "dangerous_handling",
    ],
    [
      /\b(?:safe\s+to\s+(?:handle|pick\s+up|capture|relocate)|(?:can|could|should|may|would)\s+(?:this|that|it|these|those)\s+be\s+(?:killed|trapped|captured|handled|picked\s+up|relocated))\b/,
      "dangerous_handling",
    ],
    [
      /\b(?:pesticide\s+(?:instructions?|application|use)|apply\s+(?:a\s+)?pesticide|(?:use|apply)\s+poison|poison\s+(?:it|this|that|them)|extermination\s+instructions?)\b/,
      "dangerous_handling",
    ],
    [
      /\b(?:(?:best|safest|proper|recommended)\s+(?:ways?|methods?)\s+to|(?:instructions?|steps?|tips?|advice|guide)\s+(?:for|on|to)|(?:tell|show)\s+me\s+how\s+to)\s+(?:kill(?:ing)?|exterminat(?:e|ing)|trap(?:ping)?|captur(?:e|ing)|handl(?:e|ing)|pick(?:ing)?\s+up|relocat(?:e|ing)|remov(?:e|ing)\s+(?:it|this|that|a\s+nest))\b/,
      "dangerous_handling",
    ],
    [
      /\b(?:can|could|should|may|would)\s+(?:i|we|you)\s+(?:collect|harvest|take\s+(?:it|this|that)\s+home)\b/,
      "legal_or_collection",
    ],
    [
      /\bhow\s+(?:(?:do|can|could|should|would|may)\s+(?:i|we|you)\s+|to\s+)(?:collect|harvest|take\s+(?:it|this|that)\s+home)\b/,
      "legal_or_collection",
    ],
    [
      /\b(?:can|could|should|may|would)\s+(?:this|that|it|these|those)\s+be\s+(?:collected|harvested|taken\s+home)\b/,
      "legal_or_collection",
    ],
    [
      /\b(?:legal|allowed|permit(?:ted)?|permission)\b.{0,30}\b(?:collect|harvest|capture|take|remove|relocate)\b/,
      "legal_or_collection",
    ],
    [
      /\b(?:(?:best|safest|proper|recommended)\s+(?:ways?|methods?)\s+to|(?:instructions?|steps?|tips?|advice|guide)\s+(?:for|on|to)|(?:tell|show)\s+me\s+how\s+to)\s+(?:collect(?:ing)?|harvest(?:ing)?|tak(?:e|ing)\s+(?:it|this|that)\s+home)\b/,
      "legal_or_collection",
    ],
  ];

  return patterns.find(([pattern]) => pattern.test(normalized))?.[1] ?? null;
}

export function refusalAnswer(reason: string): string {
  switch (reason) {
    case "foraging_or_ingestion":
      return "I cannot tell you that this organism is safe to eat, brew, cook, or feed to people or animals. Treat field identifications as educational only, and consult a qualified local expert before any ingestion-related decision. I can still help compare visible traits, habitat, seasonality, or lookalikes from the saved scan evidence.";
    case "medical_or_veterinary":
      return "I cannot provide medical, veterinary, poison-control, dosage, or treatment advice. If there is possible exposure, bite, sting, ingestion, or a concerning reaction, contact local emergency services, poison control, or a qualified clinician. I can help explain the stored hazard classification and identification evidence in non-treatment terms.";
    case "dangerous_handling":
      return "I cannot give instructions for dangerous handling, capture, killing, poisoning, or removal. Observe from a safe distance and follow local guidance. I can help describe safer field-observation cues from the saved scan context.";
    case "legal_or_collection":
      return "I cannot determine whether collection, harvest, or removal is legal from this scan. Rules vary by location, land manager, and species status. Check local regulations or a qualified authority before acting. I can help summarize the conservation and identification context Naturebook has saved.";
    default:
      return "I cannot help with that request, but I can answer educational questions about the saved observation, visible traits, habitat, seasonality, or lookalikes.";
  }
}
