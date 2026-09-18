import { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "./http.ts";
import type {
  ReactionPage,
  ReactionState,
  ReactionTarget,
} from "./exploreReactions.ts";

function reactionError(error: { code?: string }): never {
  if (error.code === "42501") {
    throw publicHttpError(403, "This reaction is no longer available.");
  }
  if (error.code === "22023") {
    throw publicHttpError(400, "Choose one supported emoji.");
  }
  throw new Error("Explore reaction request failed.");
}
export async function setReaction(
  userId: string,
  kind: ReactionTarget,
  id: string,
  emoji: string,
  selected: boolean,
  client: SupabaseClient,
): Promise<ReactionState> {
  const { data, error } = await client.rpc("set_explore_reaction", {
    self_id: userId,
    target_kind: kind,
    target_id: id,
    requested_emoji: emoji,
    selected,
  });
  if (error) reactionError(error);
  return data as ReactionState;
}
export async function fetchReactions(
  userId: string,
  kind: ReactionTarget,
  id: string,
  cursor: number,
  client: SupabaseClient,
): Promise<ReactionPage> {
  const { data, error } = await client.rpc("get_explore_reactions", {
    self_id: userId,
    target_kind: kind,
    target_id: id,
    after_ordinal: cursor,
    page_size: 32,
  });
  if (error) reactionError(error);
  return data as ReactionPage;
}
interface Preview extends ReactionPage {
  target_id: string;
}
export async function withReactionPreviews<T>(
  rows: T[],
  userId: string,
  kind: ReactionTarget,
  id: (row: T) => string,
  client: SupabaseClient,
): Promise<Array<T & ReactionPage>> {
  if (rows.length === 0) return [];
  if (rows.length > 100) {
    throw new Error("Reaction preview batch exceeds 100 targets.");
  }
  const { data, error } = await client.rpc("get_explore_reaction_previews", {
    self_id: userId,
    target_kind: kind,
    target_ids: rows.map(id),
  });
  if (error) reactionError(error);
  const pages = new Map(
    (data as Preview[]).map((page) => [page.target_id, page]),
  );
  return rows.map((row) => {
    const page = pages.get(id(row));
    return {
      ...row,
      reactions: page?.reactions ?? [],
      reactions_next_cursor: page?.reactions_next_cursor ?? null,
    };
  });
}
