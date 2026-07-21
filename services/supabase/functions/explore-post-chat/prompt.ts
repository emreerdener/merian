import type { ExplorePostChatContext, ExplorePostChatMessageRow } from "./types.ts";

function clean(value: unknown, max = 900): string {
  if (typeof value !== "string") return "Unavailable";
  const trimmed = value.trim();
  if (!trimmed) return "Unavailable";
  return trimmed.length > max ? `${trimmed.slice(0, max - 1)}…` : trimmed;
}

function list(value: unknown, max = 8): string {
  if (!Array.isArray(value)) return "Unavailable";
  const items = value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean)
    .slice(0, max);
  return items.length ? items.join(", ") : "Unavailable";
}

export function buildExplorePostContextBlock(context: ExplorePostChatContext): string {
  const { post, detail } = context;
  const taxonomy = [
    detail.taxonomy_kingdom,
    detail.taxonomy_phylum,
    detail.taxonomy_class,
    detail.taxonomy_order,
    detail.taxonomy_family,
    detail.taxonomy_genus,
  ].map((value) => clean(value, 100)).filter((value) => value !== "Unavailable").join(" > ");
  const similarSpecies = (detail.similar_species ?? []).slice(0, 6).map((entry) => ({
    scientific_name: clean(entry.scientific_name, 160),
    common_name: clean(entry.common_name, 160),
    reason: clean(entry.reason, 300),
    visual_traits: Array.isArray(entry.visual_traits)
      ? entry.visual_traits.slice(0, 6).map((trait) => clean(trait, 120))
      : [],
    iucn_red_list_status: clean(entry.iucn_red_list_status, 100),
  }));

  return [
    "[PUBLIC EXPLORE POST CONTEXT]",
    `Common Name: ${clean(post.species_common_name, 160)}`,
    `Scientific Name: ${clean(post.species_scientific_name, 160)}`,
    `Taxonomy: ${taxonomy || "Unavailable"}`,
    `Alternative Common Names: ${list(detail.alternative_common_names)}`,
    `Habitat: ${clean(detail.habitat_description)}`,
    `Overview: ${clean(detail.wikipedia_overview, 1200)}`,
    `Hazard Type: ${clean(detail.hazard_type, 100)}`,
    `IUCN Red List Status: ${clean(detail.iucn_red_list_status, 100)}`,
    `Published Field Notes: ${clean(detail.field_notes, 900)}`,
    `Public Identification Reasoning: ${clean(detail.ai_reasoning, 1200)}`,
    `Public Location Label: ${clean(post.public_location_label, 180)}`,
    `Month: ${post.current_month ?? "Unavailable"}`,
    `Time Of Day: ${clean(post.time_of_day, 80)}`,
    `Weather: ${clean(post.weather_condition, 120)}`,
    `Temperature F: ${post.weather_temperature_f ?? "Unavailable"}`,
    `Similar Species: ${JSON.stringify(similarSpecies).slice(0, 1200)}`,
  ].join("\n");
}

export function buildSystemInstruction(context: ExplorePostChatContext): string {
  return `Naturebook Field chat for a public Explore observation.
Answer educational questions about the published species using only the public
text context below. You cannot inspect the post's photo, video, or audio and must
say so when a question requires direct media inspection. Never imply access to
the owner's private scan, exact location, unpublished notes, chat, or comments.

Do not provide edible certainty, medical or veterinary treatment, dangerous
handling, capture, killing, poisoning, pesticide use, illegal collection, or
human identification. Be conservative around hazardous or protected organisms.
Do not reconstruct or request exact coordinates. If the identification evidence
is limited, say so. Keep answers concise, normally 2–5 short paragraphs or a
short list. If asked outside this species context, redirect to the observation.

Return JSON with exactly:
{"answer":"string","is_refusal":boolean,"refusal_reason":"string or null"}

${buildExplorePostContextBlock(context)}`;
}

export function buildUserPrompt(
  messages: ExplorePostChatMessageRow[],
  question: string,
): string {
  const history = messages.slice(-12).map((message) =>
    `${message.role === "user" ? "User" : "Naturebook"}: ${clean(message.message_text)}`
  );
  return `[CHAT HISTORY]\n${history.length ? history.join("\n") : "No prior messages."}\n\n[CURRENT USER QUESTION]\n${question}`;
}
