import { assertEquals, assertThrows } from "@std/assert";
import { requireParams } from "../_shared/http.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  decodeScanObservation,
  readScanObservationHttp,
} from "./observation.ts";

const owner = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const scan = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const body = () => ({
  initial_recovery: {
    version: 1,
    phase: "observe",
    original: { owner_id: owner, scan_id: scan },
  },
});
function request(
  value: unknown = body(),
  headers: Record<string, string> = {},
  signal?: AbortSignal,
) {
  return new Request("https://fixture.invalid/check-scan-status", {
    method: "POST",
    signal,
    headers: {
      "content-type": "application/json",
      "x-merian-initial-recovery": "observe-v1",
      ...headers,
    },
    body: JSON.stringify(value),
  });
}
function client(
  rowExists: boolean,
  status: unknown,
  fail = "",
  wait?: () => Promise<void>,
) {
  const reads: {
    table: string;
    columns: string;
    filters: Record<string, string>;
  }[] = [];
  const value = {
    from(table: string) {
      const read = {
        table,
        columns: "",
        filters: {} as Record<string, string>,
      };
      reads.push(read);
      const builder = {
        select(columns: string) {
          read.columns = columns;
          return builder;
        },
        eq(key: string, value: string) {
          read.filters[key] = value;
          return builder;
        },
        abortSignal(signal: AbortSignal) {
          signal.throwIfAborted();
          return builder;
        },
        async maybeSingle() {
          await wait?.();
          if (table === fail) {
            return {
              data: null,
              error: { message: "private failure" },
            };
          }
          if (table === "scans") {
            return {
              data: rowExists ? { id: scan } : null,
              error: null,
            };
          }
          assertEquals(table, "scan_ingestion_jobs");
          return { data: status === null ? null : { status }, error: null };
        },
      };
      return builder;
    },
  } as unknown as SupabaseClient;
  return { value, reads };
}

Deno.test("observation returns only bounded metadata from two exact owner SELECTs", async () => {
  for (const exists of [true, false]) {
    for (
      const status of [
        null,
        "processing",
        "finalizing",
        "retrying",
        "failed_retryable",
        "failed_terminal",
        "complete",
      ]
    ) {
      const c = client(exists, status);
      const response = await readScanObservationHttp(request(), owner, c.value);
      assertEquals(response.status, 200);
      assertEquals(response.headers.get("cache-control"), "no-store");
      assertEquals(await response.json(), {
        version: 1,
        phase: "observe",
        owner_id: owner,
        scan_id: scan,
        row_exists: exists,
        job_status: status,
        original_result: "unavailable",
      });
      assertEquals(c.reads, [
        {
          table: "scans",
          columns: "id",
          filters: { id: scan, user_id: owner },
        },
        {
          table: "scan_ingestion_jobs",
          columns: "status",
          filters: { scan_id: scan, user_id: owner },
        },
      ]);
    }
  }
});

Deno.test("observation rejects foreign, mixed, bulk, unknown and malformed contracts before reads", async () => {
  const good = body();
  assertEquals(requireParams(good, ["scan_id"])?.status, 400);
  const invalid: unknown[] = [
    null,
    [],
    {},
    { ...good, recovery_scan: {} },
    { ...good, scans: [] },
    { ...good, scan_id: scan },
    {
      ...good,
      initial_recovery: {
        ...good.initial_recovery,
        original: { owner_id: owner, scan_id: "bad" },
      },
    },
    { ...good, initial_recovery: null },
    { ...good, initial_recovery: { ...good.initial_recovery, version: 2 } },
    {
      ...good,
      initial_recovery: { ...good.initial_recovery, phase: "completion" },
    },
    {
      ...good,
      initial_recovery: {
        ...good.initial_recovery,
        original: { owner_id: scan, scan_id: scan },
      },
    },
    {
      ...good,
      initial_recovery: {
        ...good.initial_recovery,
        original: { owner_id: owner, scan_id: scan.toUpperCase() },
      },
    },
    {
      ...good,
      initial_recovery: {
        ...good.initial_recovery,
        original: { owner_id: owner, scan_id: scan, result: {} },
      },
    },
  ];
  for (const value of invalid) {
    assertThrows(() => decodeScanObservation(value, owner));
    const c = client(true, "complete");
    const response = await readScanObservationHttp(
      request(value),
      owner,
      c.value,
    );
    assertEquals(response.status, 503);
    assertEquals(c.reads, []);
  }
});

Deno.test("observation bounds actual/declared bytes and requires exact HTTP phase", async () => {
  const cases = [
    request(body(), { "x-merian-initial-recovery": "admission-v1" }),
    request(body(), { "content-type": "text/plain" }),
    request(body(), { "content-encoding": "gzip" }),
    request(body(), { "content-length": "-1" }),
    request(body(), { "content-length": "1025" }),
    request(body(), { "content-length": "1" }),
    request({ ...body(), padding: "x".repeat(1024) }),
  ];
  for (const req of cases) {
    const c = client(true, "complete");
    assertEquals(
      (await readScanObservationHttp(req, owner, c.value)).status,
      503,
    );
    assertEquals(c.reads, []);
  }
});

Deno.test("observation database failure and unknown job status never become a found result", async () => {
  for (const failure of ["scans", "scan_ingestion_jobs", "unknown-status"]) {
    const c = client(
      true,
      failure === "unknown-status" ? "future" : "complete",
      failure,
    );
    const response = await readScanObservationHttp(request(), owner, c.value);
    assertEquals(response.status, 503);
    assertEquals(await response.json(), {
      error: "scan_observation_unavailable",
    });
    assertEquals(c.reads.length, failure === "scans" ? 1 : 2);
  }
});

Deno.test("observation discards late read after caller cancellation without a second query", async () => {
  let entered!: () => void, release!: () => void;
  const started = new Promise<void>((resolve) => entered = resolve);
  const paused = new Promise<void>((resolve) => release = resolve);
  const c = client(true, "complete", "", async () => {
    entered();
    await paused;
  });
  const controller = new AbortController();
  const reading = readScanObservationHttp(
    request(body(), {}, controller.signal),
    owner,
    c.value,
  );
  await started;
  controller.abort();
  const response = await reading;
  assertEquals(response.status, 503);
  release();
  await Promise.resolve();
  await Promise.resolve();
  assertEquals(c.reads.length, 1);
});

Deno.test("observation shared wire fixture preserves no legacy routing and no original result", async () => {
  const fixture = JSON.parse(
    await Deno.readTextFile(
      new URL("./fixtures/observation-v1.json", import.meta.url),
    ),
  );
  assertEquals(fixture.request, body());
  assertEquals(requireParams(fixture.request, ["scan_id"])?.status, 400);
  const c = client(true, "complete");
  const response = await readScanObservationHttp(
    request(fixture.request),
    owner,
    c.value,
  );
  assertEquals(await response.json(), fixture.response);
});

Deno.test("observation branch deadline refuses an uncooperative read without starting another", async () => {
  let release!: () => void;
  const paused = new Promise<void>((resolve) => release = resolve);
  const c = client(true, "complete", "", () => paused);
  const start = performance.now();
  const response = await readScanObservationHttp(request(), owner, c.value);
  const elapsed = performance.now() - start;
  assertEquals(response.status, 503);
  assertEquals(elapsed >= 4900 && elapsed < 10000, true);
  release();
  await Promise.resolve();
  await Promise.resolve();
  assertEquals(c.reads.length, 1);
});
