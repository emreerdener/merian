import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { upsertPushDeviceRegistration } from "./db.ts";

const DEVICE_TOKEN_RE = /^[0-9a-f]{32,512}$/i;

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const paramErr = requireParams(body, [
      "device_token",
      "platform",
      "environment",
      "explore_enabled",
    ]);
    if (paramErr) return paramErr;

    const rawToken = typeof body.device_token === "string"
      ? body.device_token.trim().toLowerCase()
      : "";
    if (!DEVICE_TOKEN_RE.test(rawToken)) {
      return jsonResponse({
        error: "device_token must be a lowercase hex APNs token.",
      }, 400);
    }

    if (body.platform !== "ios") {
      return jsonResponse({ error: "platform must be 'ios'." }, 400);
    }

    if (body.environment !== "sandbox" && body.environment !== "production") {
      return jsonResponse({
        error: "environment must be 'sandbox' or 'production'.",
      }, 400);
    }

    if (typeof body.explore_enabled !== "boolean") {
      return jsonResponse({ error: "explore_enabled must be a boolean." }, 400);
    }

    if (
      body.comment_mentions_enabled !== undefined &&
      typeof body.comment_mentions_enabled !== "boolean"
    ) {
      return jsonResponse(
        { error: "comment_mentions_enabled must be a boolean." },
        400,
      );
    }

    if (
      body.community_identifications_enabled !== undefined &&
      typeof body.community_identifications_enabled !== "boolean"
    ) {
      return jsonResponse(
        { error: "community_identifications_enabled must be a boolean." },
        400,
      );
    }

    const commentMentionsEnabled =
      typeof body.comment_mentions_enabled === "boolean"
        ? body.comment_mentions_enabled
        : body.explore_enabled;
    const communityIdentificationsEnabled =
      typeof body.community_identifications_enabled === "boolean"
        ? body.community_identifications_enabled
        : body.explore_enabled;

    await upsertPushDeviceRegistration(user.id, {
      deviceToken: rawToken,
      platform: "ios",
      environment: body.environment,
      exploreEnabled: body.explore_enabled,
      commentMentionsEnabled,
      communityIdentificationsEnabled,
    }, supabaseAdmin);

    return jsonResponse({ success: true }, 200);
  })
);
