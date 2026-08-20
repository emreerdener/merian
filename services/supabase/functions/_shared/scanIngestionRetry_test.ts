import { assertEquals } from "@std/assert";

import {
  DEFAULT_SCAN_INGESTION_RETRY_SECONDS,
  scanIngestionRetryAfterIso,
} from "./scanIngestionRetry.ts";

Deno.test("scan ingestion retry defaults to a deterministic 30-second window", () => {
  const now = Date.parse("2026-08-20T18:00:00.000Z");

  assertEquals(DEFAULT_SCAN_INGESTION_RETRY_SECONDS, 30);
  assertEquals(
    scanIngestionRetryAfterIso(now),
    "2026-08-20T18:00:30.000Z",
  );
});
