import type { SupabaseClient } from "@supabase/supabase-js";

async function erasureRPC(
  client: SupabaseClient,
  name: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  const { data, error } = await client.rpc(name, args).abortSignal(
    AbortSignal.timeout(12_000),
  );
  if (error) throw new Error("publication_photo_erasure_unavailable");
  return data;
}
export function publicationPhotoErasureRepository(client: SupabaseClient) {
  return {
    claim: (objectId: string | null) =>
      erasureRPC(client, "claim_publication_photo_erasure", {
        p_object: objectId,
      }),
    finish: async (
      objectId: string,
      claimToken: string,
      success: boolean,
    ): Promise<boolean> =>
      await erasureRPC(client, "finish_publication_photo_erasure", {
        p_object: objectId,
        p_claim: claimToken,
        p_success: success,
      }) === true,
  };
}
