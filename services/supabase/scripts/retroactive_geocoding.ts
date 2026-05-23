import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

/**
 * Merian Retroactive Geocoding Migration Script
 * 
 * Loops through all database scans with valid GPS coordinates but missing
 * semantic locations, reverse-geocodes them sequentially to "City, State",
 * and updates the DB.
 * 
 * Database triggers automatically run the sanitization and obscuring algorithms
 * to cleanly populate publicLocationLabel on all shared Explore posts.
 * 
 * Run with:
 *   export SUPABASE_URL="https://your-supabase-project.supabase.co"
 *   export SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
 *   deno run --allow-net --allow-env retroactive_geocoding.ts
 */

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("❌ Error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables must be set.");
  Deno.exit(1);
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false,
  },
});

async function reverseGeocodeNominatim(lat: number, lon: number): Promise<string | null> {
  const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=jsonv2&zoom=10&addressdetails=1`;
  
  try {
    const response = await fetch(url, {
      headers: {
        "User-Agent": "MerianApp-Beta-GeocodingMigration/1.0 (contact@merian.app)",
      },
    });

    if (!response.ok) {
      console.warn(`⚠️ Nominatim API returned status: ${response.status}`);
      return null;
    }

    const data = await response.json();
    const address = data.address;

    if (!address) return null;

    // Extract city/town/village/hamlet
    const city = address.city || address.town || address.village || address.hamlet || address.municipality || address.county;
    // Extract state/province/region
    const state = address.state || address.region || address.province;

    if (city && state) {
      return `${city}, ${state}`;
    } else if (state) {
      return state;
    } else if (address.country) {
      return address.country;
    }

    return null;
  } catch (error) {
    console.error(`❌ Failed to reverse-geocode coordinates (${lat}, ${lon}):`, error);
    return null;
  }
}

async function runMigration() {
  console.log("🌍 Starting Retroactive Geocoding Migration...");
  console.log("🔗 Connected to Supabase Project:", SUPABASE_URL);

  // 1. Fetch all records that have GPS coordinates but no semantic_location
  const { data: scans, error } = await supabase
    .from("scans")
    .select("id, gps_lat_exact, gps_long_exact")
    .is("semantic_location", null)
    .not("gps_lat_exact", "is", null)
    .not("gps_long_exact", "is", null);

  if (error) {
    console.error("❌ Failed to fetch scans from database:", error.message);
    Deno.exit(1);
  }

  const totalScans = scans?.length ?? 0;
  console.log(`📋 Found ${totalScans} scan records requiring retroactive reverse-geocoding.\n`);

  if (totalScans === 0) {
    console.log("✅ Nothing to migrate. All scans have location data!");
    Deno.exit(0);
  }

  let successCount = 0;
  let skippedCount = 0;

  for (let i = 0; i < totalScans; i++) {
    const scan = scans[i];
    const lat = scan.gps_lat_exact;
    const lon = scan.gps_long_exact;

    console.log(`⏳ [${i + 1}/${totalScans}] Geocoding scan ID: ${scan.id} (${lat}, ${lon})...`);

    // Nominatim's usage policy requires a limit of 1 request per second
    const locationName = await reverseGeocodeNominatim(lat, lon);
    await new Promise((resolve) => setTimeout(resolve, 1000));

    if (!locationName) {
      console.warn(`⚠️ Skipped scan ID: ${scan.id} (could not resolve coordinates to city/state)`);
      skippedCount++;
      continue;
    }

    // 2. Update semantic_location in public.scans
    // (This automatically triggers sanitization and populates public_location_label for Explore posts)
    const { error: updateError } = await supabase
      .from("scans")
      .update({ semantic_location: locationName })
      .eq("id", scan.id);

    if (updateError) {
      console.error(`❌ Failed to update scan ID ${scan.id}:`, updateError.message);
      skippedCount++;
    } else {
      console.log(`✅ Success! Resolved scan to: "${locationName}"`);
      successCount++;
    }
  }

  console.log("\n==============================================");
  console.log("🎉 Retroactive Geocoding Complete!");
  console.log(`   - Successful Updates: ${successCount}`);
  console.log(`   - Skipped / Failed:   ${skippedCount}`);
  console.log("==============================================\n");
}

await runMigration();
