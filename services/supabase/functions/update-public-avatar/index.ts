import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { promotePublicAvatar, validatePublicAvatarRequest } from "./avatar.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const parsed = validatePublicAvatarRequest(body, user.id);
    if (parsed.error || !parsed.value) {
      return jsonResponse(
        { error: parsed.error?.message ?? "Invalid avatar request" },
        parsed.error?.status ?? 400,
      );
    }

    const { data: profile, error: profileError } = await supabaseAdmin
      .from("users")
      .select("custom_avatar_url")
      .eq("id", user.id)
      .single();

    if (profileError || !profile) {
      return jsonResponse({ error: "User profile not found." }, 404);
    }

    const promoted = await promotePublicAvatar(
      parsed.value,
      user.id,
      profile.custom_avatar_url as string | null | undefined,
    );

    const { error: updateError } = await supabaseAdmin
      .from("users")
      .update({
        custom_avatar_url: promoted.avatarUrl,
        custom_avatar_updated_at: new Date().toISOString(),
        public_avatar_url: promoted.avatarUrl,
      })
      .eq("id", user.id);

    if (updateError) {
      throw new Error(`Failed to update public avatar: ${updateError.message}`);
    }

    return jsonResponse({ avatar_url: promoted.avatarUrl }, 200);
  })
);
