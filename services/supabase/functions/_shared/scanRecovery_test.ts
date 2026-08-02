import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { PublicHttpError } from "./http.ts";
import {
  normalizeOwnedScanRecovery,
  recoverMissingOwnedScan,
} from "./scanRecovery.ts";

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

interface RecoveryRpcCall {
  name: string;
  arguments: Record<string, unknown>;
}

function recoveryClient(options: {
  boundaryData?: unknown;
  boundaryError?: { message: string } | null;
  outcome?: unknown;
  recoveryError?: { message: string } | null;
} = {}): { client: SupabaseClient; calls: RecoveryRpcCall[] } {
  const calls: RecoveryRpcCall[] = [];
  return {
    calls,
    client: {
      rpc(name: string, arguments_: Record<string, unknown>) {
        calls.push({ name, arguments: arguments_ });
        if (name === "get_media_abandoned_scan_recovery_proofs") {
          return Promise.resolve({
            data: Object.hasOwn(options, "boundaryData")
              ? options.boundaryData
              : [],
            error: options.boundaryError ?? null,
          });
        }
        if (name === "recover_missing_owned_scan") {
          return Promise.resolve({
            data: Object.hasOwn(options, "outcome")
              ? options.outcome
              : "recovered",
            error: options.recoveryError ?? null,
          });
        }
        throw new Error(`Unexpected RPC: ${name}`);
      },
    } as unknown as SupabaseClient,
  };
}

Deno.test("recoverMissingOwnedScan proves the hardened boundary before its atomic RPC", async () => {
  const { client, calls } = recoveryClient();
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");

  const recovered = await recoverMissingOwnedScan(recovery, client);

  assertEquals(recovered, true);
  assertEquals(calls, [
    {
      name: "get_media_abandoned_scan_recovery_proofs",
      arguments: {
        p_user_id: userId,
        p_scan_ids: [scanId],
      },
    },
    {
      name: "recover_missing_owned_scan",
      arguments: {
        p_scan_id: scanId,
        p_user_id: userId,
        p_recovery_scan: recovery,
      },
    },
  ]);
});

Deno.test("recoverMissingOwnedScan reports database failures truthfully", async () => {
  const { client, calls } = recoveryClient({
    recoveryError: { message: "transaction rejected recovery" },
  });
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");

  await assertRejects(
    () => recoverMissingOwnedScan(recovery, client),
    Error,
    "recoverMissingOwnedScan: transaction rejected recovery",
  );
  assertEquals(calls.length, 2);
});

Deno.test("recoverMissingOwnedScan refuses a missing hardening migration", async () => {
  const { client, calls } = recoveryClient({
    boundaryError: { message: "function is absent" },
  });
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");

  await assertRejects(
    () => recoverMissingOwnedScan(recovery, client),
    Error,
    "hardened recovery boundary unavailable: function is absent",
  );
  assertEquals(calls.length, 1);
  assertEquals(calls[0].name, "get_media_abandoned_scan_recovery_proofs");
});

Deno.test("recoverMissingOwnedScan rejects malformed or foreign boundary rows", async () => {
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");

  for (
    const boundaryData of [
      null,
      { scan_id: scanId },
      [null],
      [{ scan_id: 123 }],
      [{ scan_id: "00000000-0000-0000-0000-000000000099" }],
    ]
  ) {
    const { client, calls } = recoveryClient({ boundaryData });
    await assertRejects(
      () => recoverMissingOwnedScan(recovery, client),
      Error,
      "invalid hardened recovery boundary response",
    );
    assertEquals(calls.length, 1);
  }
});

Deno.test("recoverMissingOwnedScan maps nonrecoverable outcomes to false", async () => {
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");

  for (const outcome of ["deferred", "id_collision", "deleted"]) {
    const { client } = recoveryClient({ outcome });
    assertEquals(
      await recoverMissingOwnedScan(recovery, client),
      false,
    );
  }
});

Deno.test("recoverMissingOwnedScan fails closed on an unknown catalog outcome", async () => {
  const recovery = normalizeOwnedScanRecovery(
    validRecovery(),
    scanId,
    userId,
  );
  if (!recovery) throw new Error("Expected recovery row.");
  const { client } = recoveryClient({ outcome: "legacy_allowed" });

  await assertRejects(
    () => recoverMissingOwnedScan(recovery, client),
    Error,
    "invalid database response",
  );
});
