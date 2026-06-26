import {
  MAX_MESSAGES_PER_CONVERSATION,
  MAX_USER_MESSAGE_CHARS,
} from "./types.ts";

export function isInsightChatFeatureEnabled(
  value: string | undefined,
): boolean {
  return value === "true";
}

export function normalizeAction(value: unknown): "load" | "send" | "delete" {
  if (value === "load" || value === "send" || value === "delete") return value;
  throw Object.assign(new Error("action must be load, send, or delete."), {
    status: 400,
  });
}

export function normalizeUserMessage(value: unknown): string {
  if (typeof value !== "string") {
    throw Object.assign(new Error("message_text must be a string."), {
      status: 400,
    });
  }
  const trimmed = value.trim();
  if (!trimmed) {
    throw Object.assign(new Error("message_text cannot be empty."), {
      status: 400,
    });
  }
  if (trimmed.length > MAX_USER_MESSAGE_CHARS) {
    throw Object.assign(
      new Error(
        `message_text must be ${MAX_USER_MESSAGE_CHARS} characters or fewer.`,
      ),
      { status: 400 },
    );
  }
  return trimmed;
}

export function assertConversationHasRoom(messageCount: number): void {
  if (messageCount >= MAX_MESSAGES_PER_CONVERSATION) {
    throw Object.assign(new Error("Conversation message limit reached."), {
      status: 429,
      code: "conversation_limit_reached",
    });
  }
}

export function isSafetyCriticalQuestion(text: string): string | null {
  const normalized = text.toLowerCase();
  const patterns: Array<[RegExp, string]> = [
    [
      /\b(eat|edible|taste|cook|bake|brew|tea|forag|mushroom\s+hunt|feed\s+(it|this|to)|safe\s+to\s+consume)\b/,
      "foraging_or_ingestion",
    ],
    [
      /\b(poison control|antidote|treat|treatment|dose|dosage|medicine|medicinal|symptom|rash|bite|sting|venom|allergic reaction)\b/,
      "medical_or_veterinary",
    ],
    [
      /\b(pesticide|poison|kill it|exterminate|trap|capture|handle|pick up|relocate|collect eggs|remove nest)\b/,
      "dangerous_handling",
    ],
    [
      /\b(legal to collect|protected species|take it home|harvest|permit)\b/,
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
      return "I cannot determine whether collection, harvest, or removal is legal from this scan. Rules vary by location, land manager, and species status. Check local regulations or a qualified authority before acting. I can help summarize the conservation and identification context Merian has saved.";
    default:
      return "I cannot help with that request, but I can answer educational questions about the saved observation, visible traits, habitat, seasonality, or lookalikes.";
  }
}
