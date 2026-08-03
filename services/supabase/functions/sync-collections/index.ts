import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";

import { SyncCollectionPayload } from "./types.ts";
import {
  deleteCollections,
  fetchCollectionMemberships,
  syncMembershipDelta,
  upsertOwnedCollections,
} from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const requestBody = await parseJsonBody(req, { limit: "bulk" });
    if (requestBody instanceof Response) return requestBody;

    const rawCollections = requestBody.collections;
    if (!Array.isArray(rawCollections)) {
      return jsonResponse(
        {
          error: "Invalid payload. Expected an array of 'collections'.",
        },
        400,
      );
    }
    const collections = rawCollections as SyncCollectionPayload[];

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
      if (
        Array.isArray(c.scan_ids) &&
        c.scan_ids.length > MAX_SCAN_IDS_PER_COLLECTION
      ) {
        return jsonResponse(
          {
            error:
              `Collection "${c.id}" exceeds the scan_ids limit (max ${MAX_SCAN_IDS_PER_COLLECTION}).`,
          },
          400,
        );
      }
    }

    const isDeletedFlag = (c: SyncCollectionPayload) =>
      c.is_deleted === true || c.isDeleted === true;

    const allValidCollections = collections.filter((c) => !isDeletedFlag(c));
    const deletedCollections = collections.filter((c) => isDeletedFlag(c));

    // The RPC performs the ownership decision inside the same atomic statement
    // as the insert/update. Concurrent UUID collisions and foreign stale IDs are
    // rejected without modifying their rows.
    const { ownedCollections, ownedIds } = await upsertOwnedCollections(
      user.id,
      allValidCollections,
      supabaseAdmin,
    );

    // Do not perform downstream membership work if the guarded upsert failed.
    // Explicit deletes remain owner-scoped and foreign IDs stay skippable.
    await deleteCollections(deletedCollections, user.id, supabaseAdmin);

    const existingMemberships = await fetchCollectionMemberships(
      ownedIds,
      supabaseAdmin,
    );

    // 2. Diff-based membership sync — write exclusively the delta matrix.
    //    Both ownedCollections and ownedIds are already scoped to this user so
    //    syncMembershipDelta cannot touch foreign collections.
    await syncMembershipDelta(
      user.id,
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
  })
);
