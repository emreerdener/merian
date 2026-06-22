import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  makeHttpError,
  normalizeCommunityLocationSharing,
  normalizeCommunityNote,
} from "../_shared/communityIdentification.ts";
import { requireUuid, syncPublicAuthorIdentity } from "../_shared/explore.ts";
import { requestCommunityIdentification } from "./db.ts";

function normalizeRestoredObjectKeys(value: unknown, userId: string): string[] {
  if (value == null) return [];
  if (!Array.isArray(value)) {
    throw makeHttpError(400, "restored_object_keys must be an array.");
  }

  const normalized = value.map((entry) => {
    if (typeof entry !== "string") {
      throw makeHttpError(
        400,
        "restored_object_keys must only contain strings.",
      );
    }
    return entry.trim();
  }).filter((entry) => entry.length > 0);

  if (normalized.length > 5) {
    throw makeHttpError(
      400,
      "restored_object_keys cannot contain more than 5 items.",
    );
  }

  const expectedPrefix = `staging/${userId.toLowerCase()}/`;
  if (!normalized.every((entry) => entry.startsWith(expectedPrefix))) {
    throw makeHttpError(
      400,
      "restored_object_keys must belong to the current user.",
    );
  }

  return normalized;
}

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
    const parsedBody = await parseJsonBody(req);
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
    const restoredObjectKeys = normalizeRestoredObjectKeys(
      body.restored_object_keys,
      user.id,
    );

    await syncPublicAuthorIdentity(user.id, supabaseAdmin);

    const data = await requestCommunityIdentification(
      scanId,
      user.id,
      note,
      locationSharing,
      speciesCommonName,
      restoredObjectKeys,
      supabaseAdmin,
    );

    return jsonResponse({ success: true, data });
  })
);
