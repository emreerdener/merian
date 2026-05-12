import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface UserFollowStateRow {
  author_user_id: string;
  follower_count: number;
  following_count: number;
  viewer_is_following: boolean;
}

export async function canViewExploreAuthorProfile(
  userId: string,
  authorUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "can_view_explore_author_profile",
    {
      self_id: userId,
      target_author_user_id: authorUserId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to validate Explore author profile visibility: ${error.message}`,
    );
  }

  return data === true;
}

export async function setUserFollow(
  followerUserId: string,
  followeeUserId: string,
  isFollowing: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (isFollowing) {
    const { error } = await supabaseAdmin
      .from("user_follows")
      .upsert(
        {
          follower_user_id: followerUserId,
          followee_user_id: followeeUserId,
        },
        {
          onConflict: "follower_user_id,followee_user_id",
          ignoreDuplicates: true,
        },
      );

    if (error) {
      throw new Error(`Failed to follow Explore author: ${error.message}`);
    }
    return;
  }

  const { error } = await supabaseAdmin
    .from("user_follows")
    .delete()
    .eq("follower_user_id", followerUserId)
    .eq("followee_user_id", followeeUserId);

  if (error) {
    throw new Error(`Failed to unfollow Explore author: ${error.message}`);
  }
}

export async function fetchUserFollowState(
  viewerUserId: string,
  authorUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<UserFollowStateRow> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_user_follow_state",
    {
      self_id: viewerUserId,
      target_author_user_id: authorUserId,
    },
  );

  if (error) {
    throw new Error(`Failed to fetch Explore follow state: ${error.message}`);
  }

  const rows = (data ?? []) as UserFollowStateRow[];
  return rows[0] ?? {
    author_user_id: authorUserId,
    follower_count: 0,
    following_count: 0,
    viewer_is_following: false,
  };
}
