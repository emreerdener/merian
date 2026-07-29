import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  makeHttpError,
  normalizeCommunityLocationSharing,
  normalizeCommunityNote,
} from "../_shared/communityIdentification.ts";
import { requireUuid, syncPublicAuthorIdentity } from "../_shared/explore.ts";
import { requestCommunityIdentification } from "./db.ts";
import {
  deriveAIRequestId,
  reserveAIProviderCall,
  resolveAIRequestId,
} from "../_shared/aiQuota.ts";
import { normalizeRestoredMediaObjectKeys } from "../share-scan-to-explore/restoredMediaValidation.ts";

function normalizeSpeciesCommonName(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "species_common_name must be a string.");
  }

  const trimmed = value.trim().replace(/\s+/g, " ");
  if (trimmed.length === 0) return null;
  if (trimmed.length > 200) {
    throw makeHttpError(
      400,
      "species_common_name must be 200 characters or fewer.",
    );
  }

  return trimmed;
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "standard" });
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["scan_id"]);
    if (paramErr) return paramErr;

    const scanId = requireUuid(body.scan_id, "scan_id");
    const note = normalizeCommunityNote(body.note);
    const locationSharing = normalizeCommunityLocationSharing(
      body.location_sharing,
    );
    const speciesCommonName = normalizeSpeciesCommonName(
      body.species_common_name,
    );
    const {
      restoredObjectKeys,
      restoredVideoObjectKeys,
      restoredAudioObjectKeys,
    } = normalizeRestoredMediaObjectKeys(body, user.id);

    await syncPublicAuthorIdentity(user.id, supabaseAdmin);

    let moderationParentRequestId: string | null = null;
    const data = await requestCommunityIdentification(
      scanId,
      user.id,
      note,
      locationSharing,
      speciesCommonName,
      restoredObjectKeys,
      restoredVideoObjectKeys,
      restoredAudioObjectKeys,
      supabaseAdmin,
      {
        beforeProvider: async ({ checksumSha256, policyVersion }) => {
          moderationParentRequestId ??= resolveAIRequestId(
            req,
            body.ai_request_id,
          );
          const requestId = await deriveAIRequestId(
            moderationParentRequestId,
            `${checksumSha256}:${policyVersion}`,
          );
          return await reserveAIProviderCall(req, supabaseAdmin, {
            userId: user.id,
            operation: "explore_audio_moderation",
            requestId,
          });
        },
      },
    );

    return jsonResponse({ success: true, data });
  })
);
