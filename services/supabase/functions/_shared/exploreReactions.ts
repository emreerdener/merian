import catalog from "./emojiCatalog.json" with { type: "json" };
import { publicHttpError } from "./http.ts";

const canonicalByAlias = new Map<string, string>();
for (const entry of catalog.entries) {
  for (const alias of entry.aliases) canonicalByAlias.set(alias, entry.emoji);
}

export function canonicalReactionEmoji(value: unknown): string {
  if (typeof value !== "string" || value.length > 128) {
    throw publicHttpError(400, "Choose one supported emoji.");
  }
  const emoji = canonicalByAlias.get(value.normalize("NFC"));
  if (!emoji) throw publicHttpError(400, "Choose one supported emoji.");
  return emoji;
}

export function postReactionCapability(value: unknown): boolean {
  if (value !== undefined && typeof value !== "boolean") {
    throw publicHttpError(400, "supports_post_reactions must be a boolean.");
  }
  return value === true;
}

export type ReactionTarget = "post" | "comment";
export interface ReactionSummary {
  emoji: string;
  count: number;
  viewer_has_reacted: boolean;
  order: number;
}
export interface ReactionPage {
  reactions: ReactionSummary[];
  reactions_next_cursor: number | null;
}
export interface ReactionState {
  success: boolean;
  target_id: string;
  reaction: ReactionSummary;
  like_count?: number;
  viewer_has_liked?: boolean;
}
