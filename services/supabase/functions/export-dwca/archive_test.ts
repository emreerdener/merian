import {
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { encodeExportBatch } from "./archive.ts";
import { MULTIMEDIA_HEADERS, OCCURRENCE_HEADERS } from "./dwca.ts";
import { ClaimedExportJob, ExportWorkerError } from "./types.ts";

const decoder = new TextDecoder();
const job: ClaimedExportJob = {
  id: "00000000-0000-4000-8000-000000000201",
  userId: "00000000-0000-4000-8000-000000000202",
  exportScope: "personal",
  includePreciseCoordinates: false,
  pseudonymKeyVersion: 1,
  maxExportRows: 5_000,
  maxArchiveBytes: 8 * 1024 * 1024,
  archiveObjectKey: null,
  fileUrl: null,
  archiveReadyAt: null,
  attemptCount: 1,
  leaseExpiresAt: "2026-07-25T23:59:00.000Z",
  workPhase: "occurrence",
  occurrenceAfterId: null,
  multimediaAfterId: null,
  occurrenceRows: 0,
  multimediaRows: 0,
  csvBytes: 0,
  chunkSequence: 0,
};

Deno.test("encodeExportBatch incrementally encodes occurrence rows", async () => {
  const result = await encodeExportBatch(
    job,
    "occurrence",
    [
      {
        id: "00000000-0000-4000-8000-000000000301",
        user_id: job.userId,
        species_dictionary: { scientific_name: "Danaus plexippus" },
      },
      {
        id: "00000000-0000-4000-8000-000000000302",
        user_id: job.userId,
        species_dictionary: { scientific_name: "Quercus rubra" },
      },
    ],
    null,
  );

  const csv = decoder.decode(result.bytes);
  assertEquals(result.rowCount, 2);
  assertEquals(csv.startsWith(`${OCCURRENCE_HEADERS}\n`), true);
  assertStringIncludes(csv, "Danaus plexippus");
  assertStringIncludes(csv, "Quercus rubra");
  assertEquals(csv.endsWith("\n"), true);
});

Deno.test("encodeExportBatch emits multimedia rows without an expansion array", async () => {
  const result = await encodeExportBatch(
    { ...job, workPhase: "multimedia" },
    "multimedia",
    [{
      id: "00000000-0000-4000-8000-000000000301",
      user_id: job.userId,
      image_storage_urls: [
        "https://media.example.invalid/one.webp",
        "https://media.example.invalid/two.webp",
      ],
    }],
    null,
  );

  const csv = decoder.decode(result.bytes);
  assertEquals(result.rowCount, 2);
  assertEquals(csv.startsWith(`${MULTIMEDIA_HEADERS}\n`), true);
  assertStringIncludes(csv, "one.webp");
  assertStringIncludes(csv, "two.webp");
});

Deno.test("encodeExportBatch fails while appending beyond its fixed buffer", async () => {
  const error = await assertRejects(
    () =>
      encodeExportBatch(
        { ...job, occurrenceAfterId: job.id },
        "occurrence",
        [{
          id: "00000000-0000-4000-8000-000000000301",
          user_id: job.userId,
          ecological_interactions: ["x".repeat(256)],
        }],
        null,
        64,
      ),
    ExportWorkerError,
  );
  assertEquals(error.code, "export_too_large");
});
