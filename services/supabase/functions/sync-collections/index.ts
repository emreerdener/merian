import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

import { SyncCollectionPayload } from "./types.ts";
import {
  filterOwnedCollections,
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

    const MAX_SCAN_IDS_PER_COLLECTION = 5000;
    for (const c of collections) {
      if (Array.isArray(c.scan_ids) && c.scan_ids.length > MAX_SCAN_IDS_PER_COLLECTION) {
        return jsonResponse(
          {
            error: `Collection "${c.id}" exceeds the scan_ids limit (max ${MAX_SCAN_IDS_PER_COLLECTION}).`,
          },
          400,
        );
      }
    }

    const isDeletedFlag = (c: SyncCollectionPayload) =>
      c.is_deleted === true || c.isDeleted === true;

    const allValidCollections = collections.filter((c) => !isDeletedFlag(c));
    const deletedCollections = collections.filter((c) => isDeletedFlag(c));

    // IDOR guard: resolve which incoming collection IDs are owned by this user.
    // All downstream calls receive pre-filtered collections so no function needs
    // to re-implement the ownership check independently.
    const { ownedCollections, ownedIds } = await filterOwnedCollections(
      user.id,
      allValidCollections,
      supabaseAdmin,
    );

    // 0. Process explicit deletions first (scoped to user_id by deleteCollections).
    await deleteCollections(deletedCollections, user.id, supabaseAdmin);

    // 1. Batch upsert active owned collections + fetch existing memberships concurrently.
    const existingMemberships = await upsertCollectionsAndFetchMemberships(
      user.id,
      ownedCollections,
      ownedIds,
      supabaseAdmin,
    );

    // 2. Diff-based membership sync — write exclusively the delta matrix.
    //    Both ownedCollections and ownedIds are already scoped to this user so
    //    syncMembershipDelta cannot touch foreign collections.
    await syncMembershipDelta(
      ownedCollections,
      existingMemberships,
      ownedIds,
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
