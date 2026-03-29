import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

import { SyncCollectionPayload } from "./types.ts";
import {
  deleteCollections,
  upsertCollectionsAndFetchMemberships,
  syncMembershipDelta,
} from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let requestBody;
    try {
      requestBody = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const collections: SyncCollectionPayload[] = requestBody.collections;

    if (!collections || !Array.isArray(collections)) {
      return jsonResponse(
        {
          error: "Invalid payload. Expected an array of 'collections'.",
        },
        400,
      );
    }

    const MAX_COLLECTIONS = 200;
    if (collections.length > MAX_COLLECTIONS) {
      return jsonResponse(
        {
          error: `Too many collections (max ${MAX_COLLECTIONS}).`,
        },
        400,
      );
    }

    const isDeletedFlag = (c: SyncCollectionPayload) =>
      c.is_deleted === true || c.isDeleted === true;

    const validCollections = collections.filter((c) => !isDeletedFlag(c));
    const deletedCollections = collections.filter((c) => isDeletedFlag(c));
    const activeIds = validCollections.map((c) => c.id);

    // 0. Process explicit deletions first.
    await deleteCollections(deletedCollections, supabaseAdmin);

    // 1. Batch upsert active collections + fetch existing memberships concurrently.
    const existingMemberships = await upsertCollectionsAndFetchMemberships(
      user.id,
      validCollections,
      activeIds,
      supabaseAdmin,
    );

    // 2. Diff-based membership sync — write exclusively the delta matrix.
    await syncMembershipDelta(
      validCollections,
      existingMemberships,
      activeIds,
      supabaseAdmin,
    );

    return jsonResponse(
      {
        success: true,
        message: "Collections synchronized successfully.",
      },
      200,
    );
  }),
);
