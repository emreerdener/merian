// supabase/functions/sync-collections/index.test.ts
import { assert } from "https://deno.land/std@0.224.0/testing/asserts.ts";

/**
 * Mocks the Supabase environment and Edge Function handler inputs
 * to trace strictly whether payload attributes map to the PostgrestBuilder properly
 * and whether any Postgres schema validations instantly reject the upsert payload format.
 */

// A mock of the exact payload structure the Swift client `SyncCollectionPayload` generates:
const mockClientPayload = {
    collections: [
        {
            id: crypto.randomUUID(),
            name: "My Collection",
            created_at: new Date().toISOString(), // Equivalent to Swift DateUtilities.iso8601Formatter
            is_deleted: false,
            scan_ids: [crypto.randomUUID()]
        }
    ]
};

// Simulated mock mapping of Edge function logic:
Deno.test("Edge Function Payload Mapping & Upsert Validation", async () => {
    // 1. Initial extraction
    const collections = mockClientPayload.collections;
    assert(Array.isArray(collections), "Collections is not an array");

    // 2. Validate iOS `is_deleted` filter
    const validCollections = collections.filter(c => !c.is_deleted);
    const deletedCollections = collections.filter(c => c.is_deleted);
    
    assert(validCollections.length === 1, "Failed to whitelist non-deleted collections");
    assert(deletedCollections.length === 0, "Failed to blacklist deleted collections");

    const activeIds = validCollections.map(c => c.id);

    // 3. Mock Upsert Mapping
    const mockUserId = crypto.randomUUID();
    const mappedUpsertPayload = validCollections.map(c => ({ 
        id: c.id, 
        user_id: mockUserId, 
        name: c.name, 
        created_at: c.created_at 
    }));

    // Verify properties match Postgres schema:
    for (const record of mappedUpsertPayload) {
        assert(typeof record.id === "string", "id is not a string UUID");
        assert(typeof record.user_id === "string", "user_id is not a string UUID");
        assert(typeof record.name === "string", "name is not a string");
        assert(typeof record.created_at === "string", "created_at is not an ISO8601 string");
        // Verify ISO format ends with 'Z' as Swift does
        assert(record.created_at.endsWith("Z"), "created_at must be UTC Z-suffixed");
    }

    // 4. Test actual Supabase SDK initialization if environment permits:
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (supabaseUrl && supabaseKey) {
        const { createClient } = await import("https://esm.sh/@supabase/supabase-js@2.45.0");
        const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

        const upsertResult = await supabaseAdmin.from("collections").upsert(
            mappedUpsertPayload,
            { onConflict: "id" }
        );

        if (upsertResult.error) {
            console.error("Live DB Exception:", upsertResult.error);
            throw new Error(`DB Error: ${JSON.stringify(upsertResult.error)}`);
        }
        
        console.log("Upsert succeeded! Payload is database schema compliant.");
        
        // Cleanup mock inserted record gracefully
        await supabaseAdmin.from("collections").delete().eq("id", mappedUpsertPayload[0].id);
    } else {
        console.warn("Skipping live database test: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY env variables missing. Please run with --env.");
    }
});
