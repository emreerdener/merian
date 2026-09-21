import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { PublicHttpError } from "../_shared/http.ts";
import { admitResolution, findSpecies, persistSpecies } from "./db.ts";

function database(
  row: object | null,
  rpcData: unknown = "species-id",
  error: { message: string } | null = null,
) {
  return {
    from: () => ({
      select: () => ({
        eq: () => ({
          limit: () => ({
            maybeSingle: () => Promise.resolve({ data: row, error: null }),
          }),
        }),
      }),
    }),
    rpc: () => Promise.resolve({ data: rpcData, error }),
  } as unknown as SupabaseClient;
}
Deno.test("resolution lookup denies an existing nonpublic species", async () => {
  const error = await assertRejects(
    () =>
      findSpecies(
        database({
          id: "species-id",
          scientific_name: "Fixtureus test",
          is_public_biological: false,
        }),
        "Fixtureus test",
      ),
    PublicHttpError,
  );
  assertEquals(error.status, 404);
});
Deno.test("resolution admission maps only explicit rate exhaustion to 429", async () => {
  const limited = await assertRejects(
    () =>
      admitResolution(
        database(null, null, { message: "species_resolution_rate_limited" }),
        "viewer",
      ),
    PublicHttpError,
  );
  assertEquals(limited.status, 429);
  await assertRejects(
    () =>
      admitResolution(
        database(null, null, { message: "database unavailable" }),
        "viewer",
      ),
    Error,
    "Species resolution admission failed.",
  );
});
Deno.test("resolution persistence rejects mismatched RPC and reread identities", async () => {
  const taxon = {
    scientific_name: "Fixtureus test",
    gbif_taxon_key: 900001,
    rank: "SPECIES" as const,
    status: "ACCEPTED" as const,
    kingdom: "Plantae",
  };
  await assertRejects(
    () =>
      persistSpecies(
        database({
          id: "different-id",
          scientific_name: taxon.scientific_name,
          is_public_biological: true,
        }),
        taxon,
      ),
    Error,
    "Species resolution identity mismatch.",
  );
});

Deno.test("resolution reuses a verified GBIF key under an older stored name", async () => {
  const taxon = {
    scientific_name: "Fixtureus accepted",
    gbif_taxon_key: 900001,
    rank: "SPECIES" as const,
    status: "ACCEPTED" as const,
    kingdom: "Plantae",
  };
  const result = await persistSpecies(
    database({
      id: "species-id",
      scientific_name: "Fixtureus previous",
      gbif_taxon_key: 900001,
      is_public_biological: true,
    }),
    taxon,
  );
  assertEquals(result, {
    species_id: "species-id",
    scientific_name: "Fixtureus previous",
  });
});

Deno.test("resolution persistence requires the verified key on a reused legacy record", async () => {
  const taxon = {
    scientific_name: "Fixtureus accepted",
    gbif_taxon_key: 900001,
    rank: "SPECIES" as const,
    status: "ACCEPTED" as const,
    kingdom: "Plantae",
  };
  for (const key of [null, 900002]) {
    await assertRejects(
      () =>
        persistSpecies(
          database({
            id: "species-id",
            scientific_name: taxon.scientific_name,
            gbif_taxon_key: key,
            is_public_biological: true,
          }),
          taxon,
        ),
      Error,
      "Species resolution identity mismatch.",
    );
  }
});

Deno.test("resolution identity-policy denials use a nondisclosing public 404", async () => {
  const taxon = {
    scientific_name: "Fixtureus accepted",
    gbif_taxon_key: 900001,
    rank: "SPECIES" as const,
    status: "ACCEPTED" as const,
    kingdom: "Plantae",
  };
  for (
    const message of [
      "species_resolution_identity_conflict",
      "species_resolution_ambiguous_identity",
    ]
  ) {
    const error = await assertRejects(
      () => persistSpecies(database(null, null, { message }), taxon),
      PublicHttpError,
    );
    assertEquals(error.status, 404);
    assertEquals(error.message, "This species cannot be resolved.");
  }
  const unknown = await assertRejects(
    () =>
      persistSpecies(
        database(null, null, { message: "database unavailable" }),
        taxon,
      ),
    Error,
    "Species resolution persistence failed.",
  );
  assertEquals(unknown instanceof PublicHttpError, false);
});
