import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { makeHttpError } from "../_shared/communityIdentification.ts";

export interface UpdatedCommunityRequestRow {
  id: string;
  post_id: string;
  note: string | null;
  location_sharing: string;
  updated_at: string;
}

export async function updateCommunityIdentificationRequest(
  requestId: string,
  userId: string,
  note: string | null,
  locationSharing: string,
  supabaseAdmin: SupabaseClient,
): Promise<UpdatedCommunityRequestRow> {
  const { data: existingRequest, error: existingRequestError } =
    await supabaseAdmin
      .from("explore_community_requests")
      .select("id,post_id")
      .eq("id", requestId)
      .eq("requested_by", userId)
      .neq("status", "withdrawn")
      .single();

  if (existingRequestError || !existingRequest) {
    throw makeHttpError(404, "Community request not found.");
  }

  const existingRequestRow = existingRequest as {
    id: string;
    post_id: string;
  };

  const { data: post, error: postError } = await supabaseAdmin
    .from("explore_posts")
    .update({
      location_sharing: locationSharing,
    })
    .eq("id", existingRequestRow.post_id)
    .eq("user_id", userId)
    .is("unshared_at", null)
    .select("location_sharing")
    .single();

  if (postError || !post) {
    throw makeHttpError(404, "Community request post not found.");
  }

  const { data: request, error: requestError } = await supabaseAdmin
    .from("explore_community_requests")
    .update({
      note,
      updated_at: new Date().toISOString(),
    })
    .eq("id", requestId)
    .eq("requested_by", userId)
    .neq("status", "withdrawn")
    .select("id,post_id,note,updated_at")
    .single();

  if (requestError || !request) {
    throw makeHttpError(404, "Community request not found.");
  }

  const requestRow = request as {
    id: string;
    post_id: string;
    note: string | null;
    updated_at: string;
  };

  return {
    ...requestRow,
    location_sharing: (post as { location_sharing: string }).location_sharing,
  };
}
