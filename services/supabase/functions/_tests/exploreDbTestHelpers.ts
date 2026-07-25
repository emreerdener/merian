import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";
import type { PetIdentification } from "../_shared/identify/types.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const CONFIGURED_DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL");
const DB_URL = CONFIGURED_DB_URL ?? DEFAULT_DB_URL;

export async function withExploreDbTest(
  label: string,
  fn: (client: Client) => Promise<void>,
): Promise<void> {
  const client = new Client(DB_URL);

  try {
    await client.connect();
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (CONFIGURED_DB_URL != null) {
      throw new Error(
        `[${label}] Could not connect to configured DB integration test database ${DB_URL}: ${message}`,
        { cause: error },
      );
    }

    console.warn(
      `[${label}] Skipping DB integration test. Could not connect to ${DB_URL}: ${message}`,
    );
    return;
  }

  try {
    await client.queryArray("BEGIN");
    await fn(client);
  } finally {
    try {
      await client.queryArray("ROLLBACK");
    } catch {
      // Ignore rollback failures during cleanup.
    }
    await client.end();
  }
}

export async function insertUser(
  client: Client,
  id: string,
  publicName: string,
  publicAvatarUrl: string | null = null,
): Promise<void> {
  const email = `${publicName.toLowerCase().replaceAll(" ", "_")}@example.com`;
  await client.queryArray(
    `
      INSERT INTO auth.users (
        instance_id,
        id,
        aud,
        role,
        email,
        email_confirmed_at,
        last_sign_in_at,
        raw_app_meta_data,
        raw_user_meta_data,
        created_at,
        updated_at,
        is_anonymous
      )
      VALUES (
        '00000000-0000-0000-0000-000000000000'::uuid,
        $1::uuid,
        'authenticated',
        'authenticated',
        $2,
        pg_catalog.now(),
        pg_catalog.now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        '{}'::jsonb,
        pg_catalog.now(),
        pg_catalog.now(),
        false
      )
      ON CONFLICT (id) DO NOTHING
    `,
    [id, email],
  );

  await client.queryArray(
    `
      INSERT INTO public.users (
        id,
        email,
        public_author_name,
        public_identity_source,
        public_avatar_url,
        public_username
      )
      VALUES (
        $1,
        $2,
        $3,
        'alias',
        $4,
        public.build_unique_public_username(
          public.build_default_public_username($1::uuid),
          $1::uuid
        )
      )
      ON CONFLICT (id) DO UPDATE
      SET email = EXCLUDED.email,
          public_author_name = EXCLUDED.public_author_name,
          public_identity_source = EXCLUDED.public_identity_source,
          public_avatar_url = EXCLUDED.public_avatar_url
    `,
    [
      id,
      email,
      publicName,
      publicAvatarUrl,
    ],
  );
}

export async function insertSpecies(
  client: Client,
  id: string,
  scientificName: string,
  iucnRedListStatus = "least_concern",
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.species_dictionary (
        id,
        scientific_name,
        common_names,
        kingdom,
        phylum,
        class,
        "order",
        family,
        genus,
        native_region,
        iucn_red_list_status
      )
      VALUES (
        $1,
        $2,
        '{"en":"Test Species"}'::jsonb,
        'Plantae',
        'Tracheophyta',
        'Magnoliopsida',
        'Rosales',
        'Rosaceae',
        'Rosa',
        'North America',
        $3
      )
    `,
    [id, scientificName, iucnRedListStatus],
  );
}

type InsertScanOptions = {
  id: string;
  userId: string;
  speciesId: string;
  latitude: number;
  longitude: number;
  geoprivacy: "open" | "obscured" | "private";
  gpsLatPublic?: number | null;
  gpsLongPublic?: number | null;
  imageUrl?: string;
  imageUrls?: string[];
  aiConfidenceScore?: number;
  aiReasoning?: string | null;
  inferenceTier?: string;
  imageQualityScore?: number | null;
  confirmedSpeciesId?: string | null;
  isTombstoned?: boolean;
  semanticLocation?: string | null;
  publicLocationLabel?: string | null;
  candidates?: Array<Record<string, unknown>> | null;
  petIdentification?: PetIdentification | null;
};

export async function insertScan(
  client: Client,
  options: InsertScanOptions,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.scans (
        id,
        user_id,
        species_id,
        confirmed_species_id,
        image_storage_urls,
        ai_confidence_score,
        ai_reasoning,
        inference_tier,
        image_quality_score,
        gps_lat_exact,
        gps_long_exact,
        gps_lat_public,
        gps_long_public,
        geoprivacy,
        is_tombstoned,
        semantic_location,
        public_location_label,
        candidates,
        pet_identification
      )
      VALUES (
        $1,
        $2,
        $3,
        $4,
        $5::text[],
        $6,
        $7,
        $8,
        $9,
        $10,
        $11,
        $12,
        $13,
        $14,
        $15,
        $16,
        $17,
        $18::jsonb,
        $19::jsonb
      )
    `,
    [
      options.id,
      options.userId,
      options.speciesId,
      options.confirmedSpeciesId ?? null,
      options.imageUrls ??
        [options.imageUrl ?? "https://media.merian.app/test-image.webp"],
      options.aiConfidenceScore ?? 0.9,
      options.aiReasoning ?? null,
      options.inferenceTier ?? "flash",
      options.imageQualityScore ?? null,
      options.latitude,
      options.longitude,
      options.gpsLatPublic ?? null,
      options.gpsLongPublic ?? null,
      options.geoprivacy,
      options.isTombstoned ?? false,
      options.semanticLocation ?? null,
      options.publicLocationLabel ?? null,
      options.candidates == null ? null : JSON.stringify(options.candidates),
      options.petIdentification == null
        ? null
        : JSON.stringify(options.petIdentification),
    ],
  );
}

type InsertExplorePostOptions = {
  id: string;
  userId: string;
  scanId: string;
  sharedAt?: string | null;
  fieldNotes?: string | null;
  speciesCommonName?: string | null;
  locationSharing?: "open" | "obscured" | "private";
  refreshMedia?: boolean;
};

export async function insertExplorePost(
  client: Client,
  options: InsertExplorePostOptions,
): Promise<void> {
  await client.queryArray(
    `
      INSERT INTO public.explore_posts (
        id,
        user_id,
        scan_id,
        shared_at,
        field_notes,
        species_common_name,
        location_sharing
      )
      VALUES ($1, $2, $3, COALESCE($4::timestamptz, now()), $5, $6, $7)
    `,
    [
      options.id,
      options.userId,
      options.scanId,
      options.sharedAt ?? null,
      options.fieldNotes ?? null,
      options.speciesCommonName ?? null,
      options.locationSharing ?? "open",
    ],
  );

  if (options.refreshMedia !== false) {
    await client.queryArray(
      "SELECT public.refresh_explore_post_media($1::uuid)",
      [options.id],
    );
  }
}
