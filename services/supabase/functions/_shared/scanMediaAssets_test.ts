import {
  assertEquals,
  assertRejects,
} from "https://deno.land/std@0.224.0/testing/asserts.ts";
import type { SupabaseClient } from "@supabase/supabase-js";

import { MEDIA_BUDGETS } from "./mediaBudgets.ts";
import {
  createStagedScanMediaAssets,
  type StagedScanMediaAssetInput,
} from "./scanMediaAssets.ts";

interface FakeResponse {
  data: unknown;
  error: {
    code?: string;
    message: string;
  } | null;
}

type QueryMode = "select" | "insert" | "update";

interface ExpectedQuery {
  mode: QueryMode;
  response: FakeResponse;
}

class FakeSupabaseClient {
  readonly insertedRows: unknown[][] = [];
  readonly updates: Array<Record<string, unknown>> = [];
  readonly filters: Array<
    { operator: string; column: string; value: unknown }
  > = [];

  constructor(private readonly expectedQueries: ExpectedQuery[]) {}

  from(_table: string): FakeQuery {
    return new FakeQuery(this);
  }

  take(mode: QueryMode): FakeResponse {
    const expected = this.expectedQueries.shift();
    assertEquals(expected?.mode, mode, `unexpected ${mode} query`);
    if (!expected) {
      throw new Error(`No fake response remains for ${mode}`);
    }
    return expected.response;
  }

  assertExhausted(): void {
    assertEquals(this.expectedQueries.length, 0);
  }
}

class FakeQuery {
  private mode: QueryMode = "select";

  constructor(private readonly client: FakeSupabaseClient) {}

  select(_columns?: string): this {
    return this;
  }

  insert(rows: unknown[]): this {
    this.mode = "insert";
    this.client.insertedRows.push(rows);
    return this;
  }

  update(values: Record<string, unknown>): this {
    this.mode = "update";
    this.client.updates.push(values);
    return this;
  }

  eq(column: string, value: unknown): this {
    this.client.filters.push({ operator: "eq", column, value });
    return this;
  }

  in(column: string, value: unknown[]): this {
    this.client.filters.push({ operator: "in", column, value });
    return this;
  }

  order(_column: string, _options?: unknown): this {
    return this;
  }

  maybeSingle(): this {
    return this;
  }

  then(
    onFulfilled: (response: FakeResponse) => unknown,
    onRejected?: (reason: unknown) => unknown,
  ): Promise<unknown> {
    return Promise.resolve(this.client.take(this.mode)).then(
      onFulfilled,
      onRejected,
    );
  }
}

const userId = "00000000-0000-4000-8000-000000000001";
const clientScanId = "00000000-0000-4000-8000-000000000002";

function input(
  suffix: string,
  orderIndex: number,
): StagedScanMediaAssetInput {
  return {
    userId,
    clientScanId,
    uploadSessionId: "00000000-0000-4000-8000-000000000003",
    kind: "image",
    role: "display",
    storageKey: `staging/${userId}/${suffix}.webp`,
    orderIndex,
    contentType: "image/webp",
    byteSize: 42,
  };
}

function candidate(
  assetInput: StagedScanMediaAssetInput,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: `00000000-0000-4000-8000-00000000000${assetInput.orderIndex + 4}`,
    user_id: assetInput.userId,
    client_scan_id: assetInput.clientScanId,
    upload_session_id: assetInput.uploadSessionId,
    kind: assetInput.kind,
    role: assetInput.role,
    content_type: assetInput.contentType,
    byte_size: assetInput.byteSize ?? null,
    status: "staged",
    failure_reason: null,
    storage_key: assetInput.storageKey,
    order_index: assetInput.orderIndex,
    ...overrides,
  };
}

function client(
  expectedQueries: ExpectedQuery[],
): { fake: FakeSupabaseClient; supabase: SupabaseClient } {
  const fake = new FakeSupabaseClient(expectedQueries);
  return {
    fake,
    supabase: fake as unknown as SupabaseClient,
  };
}

Deno.test("createStagedScanMediaAssets inserts missing rows and returns input order", async () => {
  const first = input("first", 0);
  const second = input("second", 1);
  const firstInserted = candidate(first);
  const secondInserted = candidate(second);
  const { fake, supabase } = client([
    { mode: "select", response: { data: [], error: null } },
    { mode: "select", response: { data: [], error: null } },
    {
      mode: "insert",
      response: {
        // PostgREST ordering must not be trusted for identity attachment.
        data: [secondInserted, firstInserted],
        error: null,
      },
    },
  ]);

  const rows = await createStagedScanMediaAssets(
    [first, second],
    supabase,
  );

  assertEquals(rows.map((row) => row.storage_key), [
    first.storageKey,
    second.storageKey,
  ]);
  assertEquals(fake.insertedRows.length, 1);
  assertEquals(fake.insertedRows[0].length, 2);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets reuses a committed lost-response row", async () => {
  const assetInput = input("lost-response", 0);
  const existing = candidate(assetInput);
  const { fake, supabase } = client([
    { mode: "select", response: { data: [existing], error: null } },
    { mode: "select", response: { data: [], error: null } },
  ]);

  const rows = await createStagedScanMediaAssets([assetInput], supabase);

  assertEquals(rows, [{
    id: existing.id,
    storage_key: existing.storage_key,
    upload_session_id: existing.upload_session_id,
    order_index: existing.order_index,
    ...existing,
  }]);
  assertEquals(fake.insertedRows, []);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets reactivates the original retryable row and session", async () => {
  const assetInput = input("retryable", 0);
  const failed = candidate(assetInput, {
    status: "failed",
    failure_reason: "scan_finalization_failed",
  });
  const reactivated = {
    id: failed.id,
    storage_key: failed.storage_key,
    upload_session_id: failed.upload_session_id,
    order_index: failed.order_index,
  };
  const { fake, supabase } = client([
    { mode: "select", response: { data: [failed], error: null } },
    {
      mode: "select",
      response: {
        data: [{ scan_id: clientScanId, status: "failed_retryable" }],
        error: null,
      },
    },
    { mode: "update", response: { data: reactivated, error: null } },
  ]);

  const rows = await createStagedScanMediaAssets([assetInput], supabase);

  assertEquals(rows, [reactivated]);
  assertEquals(fake.updates.length, 1);
  assertEquals(fake.updates[0].status, "staged");
  assertEquals(fake.updates[0].failure_reason, null);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets never reactivates a terminal job", async () => {
  const assetInput = input("terminal", 0);
  const failed = candidate(assetInput, {
    status: "failed",
    failure_reason: "moderation_rejected",
  });
  const { fake, supabase } = client([
    { mode: "select", response: { data: [failed], error: null } },
    {
      mode: "select",
      response: {
        data: [{ scan_id: clientScanId, status: "failed_terminal" }],
        error: null,
      },
    },
  ]);

  await assertRejects(
    () => createStagedScanMediaAssets([assetInput], supabase),
    Error,
    "terminal staging registration cannot be retried",
  );
  assertEquals(fake.updates, []);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets validates every failed row before reactivation", async () => {
  const retryableInput = input("retryable-first", 0);
  const rejectedInput = input("rejected-second", 1);
  const retryable = candidate(retryableInput, {
    status: "failed",
    failure_reason: "scan_finalization_failed",
  });
  const rejected = candidate(rejectedInput, {
    status: "failed",
    failure_reason: "moderation_rejected",
  });
  const { fake, supabase } = client([
    {
      mode: "select",
      response: { data: [retryable, rejected], error: null },
    },
    { mode: "select", response: { data: [], error: null } },
  ]);

  await assertRejects(
    () =>
      createStagedScanMediaAssets(
        [retryableInput, rejectedInput],
        supabase,
      ),
    Error,
    "terminal staging registration cannot be retried",
  );
  assertEquals(fake.updates, []);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets validates every terminal job before reactivation", async () => {
  const retryableInput = input("retryable-existing", 0);
  const impossibleInput = {
    ...input("job-without-media-row", 0),
    clientScanId: "00000000-0000-4000-8000-000000000020",
  };
  const retryable = candidate(retryableInput, {
    status: "failed",
    failure_reason: "scan_finalization_failed",
  });
  const { fake, supabase } = client([
    {
      mode: "select",
      response: { data: [retryable], error: null },
    },
    {
      mode: "select",
      response: {
        data: [
          { scan_id: clientScanId, status: "failed_retryable" },
          {
            scan_id: impossibleInput.clientScanId,
            status: "complete",
          },
        ],
        error: null,
      },
    },
  ]);

  await assertRejects(
    () =>
      createStagedScanMediaAssets(
        [retryableInput, impossibleInput],
        supabase,
      ),
    Error,
    "terminal staging registration cannot be retried",
  );
  assertEquals(fake.updates, []);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets never inserts media for a completed scan id", async () => {
  const assetInput = input("completed", 0);
  const { fake, supabase } = client([
    { mode: "select", response: { data: [], error: null } },
    {
      mode: "select",
      response: {
        data: [{ scan_id: clientScanId, status: "complete" }],
        error: null,
      },
    },
  ]);

  await assertRejects(
    () => createStagedScanMediaAssets([assetInput], supabase),
    Error,
    "terminal staging registration cannot be retried",
  );
  assertEquals(fake.insertedRows, []);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets converges after a concurrent unique winner", async () => {
  const assetInput = input("race", 0);
  const winner = candidate(assetInput, {
    id: "00000000-0000-4000-8000-000000000099",
  });
  const { fake, supabase } = client([
    { mode: "select", response: { data: [], error: null } },
    { mode: "select", response: { data: [], error: null } },
    {
      mode: "insert",
      response: {
        data: null,
        error: { code: "23505", message: "duplicate key" },
      },
    },
    { mode: "select", response: { data: [winner], error: null } },
    { mode: "select", response: { data: [], error: null } },
  ]);

  const rows = await createStagedScanMediaAssets([assetInput], supabase);

  assertEquals(rows[0].id, winner.id);
  assertEquals(fake.insertedRows.length, 1);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets ignores only migration-marked superseded rows", async () => {
  const assetInput = input("superseded", 0);
  const canonical = candidate(assetInput);
  const superseded = candidate(assetInput, {
    id: "00000000-0000-4000-8000-000000000098",
    status: "failed",
    failure_reason: "superseded_staging_registration",
  });
  const { fake, supabase } = client([
    {
      mode: "select",
      response: { data: [superseded, canonical], error: null },
    },
    { mode: "select", response: { data: [], error: null } },
  ]);

  const rows = await createStagedScanMediaAssets([assetInput], supabase);

  assertEquals(rows[0].id, canonical.id);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets replaces only a database-fenced identity-merge manifest", async () => {
  const requested = input("target-owner-reupload", 0);
  const retired = candidate(requested, {
    id: "00000000-0000-4000-8000-000000000097",
    storage_key: "staging/00000000-0000-4000-8000-000000000009/source.webp",
    status: "failed",
    failure_reason: "superseded_identity_merge_staging",
  });
  const inserted = candidate(requested);
  const { fake, supabase } = client([
    {
      mode: "select",
      response: { data: [retired], error: null },
    },
    {
      mode: "select",
      response: {
        data: [{
          scan_id: clientScanId,
          status: "failed_retryable",
          stage: "identity_merge_interrupted",
        }],
        error: null,
      },
    },
    {
      mode: "insert",
      response: { data: [inserted], error: null },
    },
  ]);

  const rows = await createStagedScanMediaAssets([requested], supabase);

  assertEquals(rows[0].storage_key, requested.storageKey);
  assertEquals(fake.insertedRows.length, 1);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets composes a signing subset with unrequested rows for one scan", async () => {
  const requested = input("requested", 0);
  const omitted = candidate(input("omitted", 1));
  const requestedRow = candidate(requested);
  const { fake, supabase } = client([
    {
      mode: "select",
      response: { data: [omitted, requestedRow], error: null },
    },
    { mode: "select", response: { data: [], error: null } },
  ]);

  const rows = await createStagedScanMediaAssets([requested], supabase);

  assertEquals(rows[0].id, requestedRow.id);
  assertEquals(fake.insertedRows, []);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets appends staged recovery media to a foreground subset", async () => {
  const existingInput = input("existing", 0);
  const appendedInput = input("appended", 1);
  const appended = candidate(appendedInput);
  const { fake, supabase } = client([
    {
      mode: "select",
      response: { data: [candidate(existingInput)], error: null },
    },
    {
      mode: "select",
      response: {
        // An inline foreground generation may still be processing while its
        // durable queue copy signs staged recovery media.
        data: [{
          scan_id: clientScanId,
          status: "processing",
          stage: "ai_inference_started",
        }],
        error: null,
      },
    },
    {
      mode: "insert",
      response: { data: [appended], error: null },
    },
  ]);

  const rows = await createStagedScanMediaAssets(
    [existingInput, appendedInput],
    supabase,
  );

  assertEquals(rows.map((row) => row.storage_key), [
    existingInput.storageKey,
    appendedInput.storageKey,
  ]);
  assertEquals(fake.insertedRows.length, 1);
  fake.assertExhausted();
});

Deno.test("createStagedScanMediaAssets caps the composed active scan manifest", async () => {
  const requested = input("seventh", 0);
  const existingRows = Array.from(
    { length: MEDIA_BUDGETS.maxStagingFiles },
    (_, index) => candidate(input(`existing-${index}`, index)),
  );
  const { fake, supabase } = client([
    {
      mode: "select",
      response: { data: existingRows, error: null },
    },
  ]);

  await assertRejects(
    () => createStagedScanMediaAssets([requested], supabase),
    Error,
    "staged media budget exceeded for client scan",
  );
  assertEquals(fake.insertedRows, []);
  fake.assertExhausted();
});
