import { Client } from "https://deno.land/x/postgres@v0.19.3/mod.ts";

const DEFAULT_DB_URL =
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const DB_URL = Deno.env.get("SUPABASE_DB_TEST_URL") ?? DEFAULT_DB_URL;

export async function withExploreDbTest(
  label: string,
  fn: (client: Client) => Promise<void>,
): Promise<void> {
  const client = new Client(DB_URL);

  try {
    await client.connect();
  } catch (error) {
    console.warn(
      `[${label}] Skipping DB integration test. Could not connect to ${DB_URL}: ${
        error instanceof Error ? error.message : String(error)
      }`,
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
      VALUES ($1, $2, $3, 'alias', $4, public.build_default_public_username($1::uuid))
    `,
    [
      id,
      `${publicName.toLowerCase().replaceAll(" ", "_")}@example.com`,
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
        descriptions,
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
        '{}'::jsonb,
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
  imageQualityScore?: number | null;
  confirmedSpeciesId?: string | null;
  isTombstoned?: boolean;
  semanticLocation?: string | null;
  publicLocationLabel?: string | null;
  candidates?: Array<Record<string, unknown>> | null;
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
        image_quality_score,
        gps_lat_exact,
        gps_long_exact,
        gps_lat_public,
        gps_long_public,
        geoprivacy,
        is_tombstoned,
        semantic_location,
        public_location_label,
        candidates
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
        $16::jsonb
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
}
