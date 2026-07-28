import {
  assertEquals,
  assertRejects,
  assertThrows,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import { PublicHttpError } from "./http.ts";
import {
  normalizeOwnedScanRecovery,
  recoverMissingOwnedScan,
  scanIngestionJobAllowsRecovery,
} from "./scanRecovery.ts";
import type { ScanIngestionJobRow } from "./scanIngestionJobs.ts";

const scanId = "00000000-0000-0000-0000-000000000001";
const userId = "00000000-0000-0000-0000-000000000002";

function validRecovery(): Record<string, unknown> {
  return {
    id: scanId,
    user_id: userId,
    species_id: "00000000-0000-0000-0000-000000000003",
    confirmed_species_id: null,
    image_storage_urls: [],
    timestamp: "2026-07-27T18:00:00Z",
    gps_lat_exact: 30.2672,
    gps_long_exact: -97.7431,
    gps_lat_public: 1,
    gps_long_public: 1,
    gps_elevation: 150,
    geoprivacy: "open",
    weather_condition: "Clear",
    weather_temperature_f: 86,
    ai_confidence_score: 0.94,
    ecology_type: "wild",
    is_invasive: false,
    invasive_status_region: null,
    invasive_rationale: null,
    invasive_confidence: null,
    is_live_capture: true,
    is_biological_subject: true,
    ai_reasoning: "Long bill and dark crown.",
    semantic_location: "Austin, Texas",
    public_location_label: "Austin, Texas",
    inference_tier: "flash",
    image_quality_score: 82,
    user_identification_override: null,
    user_confirmed_identification: false,
    user_review_state: "unreviewed",
  };
}

Deno.test("owned scan recovery derives owner, identity, and open public coordinates", () => {
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );

  assertEquals(recovery?.id, scanId);
  assertEquals(recovery?.user_id, userId);
  assertEquals(recovery?.gps_lat_public, 30.2672);
  assertEquals(recovery?.gps_long_public, -97.7431);
  assertEquals(recovery?.image_storage_urls, []);
  assertEquals(recovery?.timestamp, "2026-07-27T18:00:00.000Z");
});

Deno.test("owned scan recovery never exposes private public location", () => {
  const payload = validRecovery();
  payload.geoprivacy = "private";

  const recovery = normalizeOwnedScanRecovery(payload, scanId, userId);

  assertEquals(recovery?.gps_lat_exact, 30.2672);
  assertEquals(recovery?.gps_long_exact, -97.7431);
  assertEquals(recovery?.gps_lat_public, null);
  assertEquals(recovery?.gps_long_public, null);
  assertEquals(recovery?.public_location_label, null);
});

Deno.test("owned scan recovery rejects a mismatched owner", () => {
  const payload = validRecovery();
  payload.user_id = "00000000-0000-0000-0000-000000000099";

  const error = assertThrows(() =>
    normalizeOwnedScanRecovery(payload, scanId, userId)
  );
  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 400);
});

Deno.test("owned scan recovery accepts media only through staging keys", () => {
  const payload = validRecovery();
  payload.image_storage_urls = ["https://attacker.example/image.webp"];

  const error = assertThrows(() =>
    normalizeOwnedScanRecovery(payload, scanId, userId)
  );
  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 400);
});

Deno.test("owned scan recovery rejects invalid confidence", () => {
  const payload = validRecovery();
  payload.ai_confidence_score = 1.2;

  const error = assertThrows(() =>
    normalizeOwnedScanRecovery(payload, scanId, userId)
  );
  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 400);
});

Deno.test("owned scan recovery requires coordinate pairs", () => {
  const payload = validRecovery();
  payload.gps_long_exact = null;

  const error = assertThrows(() =>
    normalizeOwnedScanRecovery(payload, scanId, userId)
  );
  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 400);
});

Deno.test("owned scan recovery requires canonical UUID identities", () => {
  const payload = validRecovery();
  payload.id = "not-a-scan-id";

  const error = assertThrows(() =>
    normalizeOwnedScanRecovery(payload, "not-a-scan-id", userId)
  );
  assertEquals(error instanceof PublicHttpError, true);
  assertEquals((error as PublicHttpError).status, 400);
});

Deno.test("recoverMissingOwnedScan inserts with duplicate protection", async () => {
  const calls: Array<{
    value: unknown;
    options: unknown;
  }> = [];
  const supabase = {
    from(table: string) {
      if (table === "scan_ingestion_jobs") {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          maybeSingle() {
            return Promise.resolve({ data: null, error: null });
          },
        };
      }
      assertEquals(table, "scans");
      return {
        upsert(value: unknown, options: unknown) {
          calls.push({ value, options });
          return Promise.resolve({ error: null });
        },
      };
    },
  } as unknown as SupabaseClient;
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");

  const recovered = await recoverMissingOwnedScan(recovery, supabase);

  assertEquals(recovered, true);
  assertEquals(calls, [{
    value: recovery,
    options: { onConflict: "id", ignoreDuplicates: true },
  }]);
});

Deno.test("recoverMissingOwnedScan reports database failures truthfully", async () => {
  const supabase = {
    from(table: string) {
      if (table === "scan_ingestion_jobs") {
        return {
          select() {
            return this;
          },
          eq() {
            return this;
          },
          maybeSingle() {
            return Promise.resolve({ data: null, error: null });
          },
        };
      }
      return {
        upsert() {
          return Promise.resolve({
            error: { message: "trigger rejected insert" },
          });
        },
      };
    },
  } as unknown as SupabaseClient;
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");

  await assertRejects(
    () => recoverMissingOwnedScan(recovery, supabase),
    Error,
    "Failed to recover missing scan: trigger rejected insert",
  );
});

function ingestionJob(
  status: ScanIngestionJobRow["status"],
  stage = "background_ingestion_failed",
  lastError: string | null = null,
): ScanIngestionJobRow {
  return {
    id: "00000000-0000-0000-0000-000000000010",
    scan_id: scanId,
    user_id: userId,
    endpoint: "identify-multimodal",
    status,
    stage,
    attempt_count: 1,
    last_error: lastError,
  };
}

Deno.test("owned scan recovery defers to active and retryable ingestion", () => {
  for (
    const status of [
      "processing",
      "finalizing",
      "retrying",
      "failed_retryable",
    ] as const
  ) {
    assertEquals(scanIngestionJobAllowsRecovery(ingestionJob(status)), false);
  }
});

Deno.test("owned scan recovery permits legacy and safely terminal missing rows", () => {
  assertEquals(scanIngestionJobAllowsRecovery(null), true);
  assertEquals(
    scanIngestionJobAllowsRecovery(ingestionJob("complete", "scan_inserted")),
    true,
  );
  assertEquals(
    scanIngestionJobAllowsRecovery(ingestionJob("failed_terminal")),
    true,
  );
});

Deno.test("owned scan recovery never bypasses terminal policy rejection", () => {
  for (
    const [stage, lastError] of [
      [
        "moderation_rejected",
        "Multimodal media rejected by moderation.",
      ],
      ["moderation_rejected", "Media rejected by moderation."],
      ["ai_inference_non_stop_finish", "AI finish reason: SAFETY"],
      [
        "ai_inference_non_stop_finish",
        "AI finish reason: PROHIBITED_CONTENT",
      ],
    ]
  ) {
    assertEquals(
      scanIngestionJobAllowsRecovery(
        ingestionJob(
          "failed_terminal",
          stage,
          lastError,
        ),
      ),
      false,
    );
  }
});

Deno.test("owned scan recovery permits legacy operational errors misclassified by text", () => {
  assertEquals(
    scanIngestionJobAllowsRecovery(
      ingestionJob(
        "failed_terminal",
        "moderation_rejected",
        "Database trigger rejected insert.",
      ),
    ),
    true,
  );
});
