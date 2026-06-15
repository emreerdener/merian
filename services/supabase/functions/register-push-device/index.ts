// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { upsertPushDeviceRegistration } from "./db.ts";

const DEVICE_TOKEN_RE = /^[0-9a-f]{32,512}$/i;

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

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

    const commentMentionsEnabled =
      typeof body.comment_mentions_enabled === "boolean"
        ? body.comment_mentions_enabled
        : body.explore_enabled;

    await upsertPushDeviceRegistration(user.id, {
      deviceToken: rawToken,
      platform: "ios",
      environment: body.environment,
      exploreEnabled: body.explore_enabled,
      commentMentionsEnabled,
    }, supabaseAdmin);

    return jsonResponse({ success: true }, 200);
  })
);
