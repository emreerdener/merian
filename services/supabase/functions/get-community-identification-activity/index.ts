import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeCursorTimestamp,
  normalizeLimit,
  requireUuid,
} from "../_shared/explore.ts";
import { makeHttpError } from "../_shared/communityIdentification.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { fetchCommunityIdentificationActivity } from "./db.ts";
import type {
  CommunityIdentificationActivityGroup,
  CommunityIdentificationActivityScope,
} from "./db.ts";

function normalizeActivityScope(
  value: unknown,
): CommunityIdentificationActivityScope {
  if (value == null) return "all";
  if (value === "all" || value === "mine") return value;
  throw makeHttpError(400, "scope must be one of: all, mine.");
}

function normalizeActivityGroup(
  value: unknown,
): CommunityIdentificationActivityGroup {
  if (value == null) return "all";
  if (
    value === "all" ||
    value === "plants" ||
    value === "birds" ||
    value === "insects" ||
    value === "fungi" ||
    value === "mammals" ||
    value === "reptiles_amphibians"
  ) {
    return value;
  }
  throw makeHttpError(
    400,
    "group must be one of: all, plants, birds, insects, fungi, mammals, reptiles_amphibians.",
  );
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

    const limit = normalizeLimit(body.limit, 30, 100);
    const beforeActivityAt = normalizeCursorTimestamp(
      body.before_activity_at,
      "before_activity_at",
    );
    const beforeActivityId = body.before_activity_id == null
      ? null
      : requireUuid(body.before_activity_id, "before_activity_id");
    const scope = normalizeActivityScope(body.scope);
    const group = normalizeActivityGroup(body.group);

    if ((beforeActivityAt == null) !== (beforeActivityId == null)) {
      throw makeHttpError(
        400,
        "before_activity_at and before_activity_id must be provided together.",
      );
    }

    const rows = await fetchCommunityIdentificationActivity(
      user.id,
      scope,
      group,
      limit,
      { beforeActivityAt, beforeActivityId },
      supabaseAdmin,
    );

    return jsonResponse({ data: rows }, 200);
  })
);
