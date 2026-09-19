import { requireUuid } from "../_shared/explore.ts";

export interface ExplorePostReactor {
  user_id: string;
  display_name: string;
  username: string;
  avatar_url: string | null;
  emojis: string[];
}
export interface ExplorePostReactorsPage {
  total_count: number;
  preview_names: string[];
  reactors: ExplorePostReactor[];
  next_cursor: string | null;
}
export function parseReactorsRequest(body: Record<string, unknown>) {
  return {
    postId: requireUuid(body.post_id, "post_id"),
    afterUserId: body.after_user_id == null
      ? null
      : requireUuid(body.after_user_id, "after_user_id"),
  };
}
