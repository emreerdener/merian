import { assertEquals, assertRejects, assertStringIncludes } from "@std/assert";
import { encodeExportBatch } from "./archive.ts";
import { calculateCrc32 } from "./crc32.ts";
import {
  DWCA_META_XML,
  MULTIMEDIA_HEADERS,
  OCCURRENCE_HEADERS,
} from "./dwca.ts";
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
  assertEquals(result.crc32, calculateCrc32(result.bytes));
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
  assertEquals(result.crc32, calculateCrc32(result.bytes));
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

Deno.test("resumed historical exports retain the persisted twenty-column chunk format", async () => {
  // A previously uploaded row from the original encoder, not rebuilt from current scan state.
  const persistedRow =
    '"old","HumanObservation","Naturebook Citizen Scientist","","Fixtureus oldus","","","","","","","","","50000","unknown","not_applicable","","","","0.75"';
  const result = await encodeExportBatch(
    { ...job, occurrenceAfterId: "old", occurrenceRows: 1, chunkSequence: 1 },
    "occurrence",
    [{
      id: "new",
      user_id: null,
      species_dictionary: { scientific_name: "Fixtureus newus" },
      ai_confidence_score: 0.75,
    }],
    null,
  );
  const resumed = decoder.decode(result.bytes);
  assertEquals(
    resumed,
    persistedRow.replace('"old",', '"new",').replace(
      "Fixtureus oldus",
      "Fixtureus newus",
    ) + "\n",
  );
  const combined = `${OCCURRENCE_HEADERS}\n${persistedRow}\n${resumed}`;
  for (const row of combined.trim().split("\n")) {
    assertEquals(row.split(",").length, 20);
  }
  const core = DWCA_META_XML.split("</core>")[0];
  assertEquals([...core.matchAll(/<field index=/g)].length, 19);
  assertEquals(core.includes('index="20"'), false);
});
