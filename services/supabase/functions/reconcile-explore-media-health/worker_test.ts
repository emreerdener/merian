import { assertEquals, assertRejects } from "@std/assert";

import type { R2Config } from "../_shared/aws.ts";
import type {
  ExploreMediaHealthClaim,
  ExploreMediaHealthRunInsert,
} from "./db.ts";
import { createReconcileExploreMediaHealthHandler } from "./handler.ts";
import {
  inspectExploreMediaClaim,
  reconcileExploreMediaHealth,
} from "./worker.ts";

const R2_CONFIG = {
  s3Client: {} as never,
  bucketName: "bucket",
  endpoint: "https://r2.example.test",
} satisfies R2Config;
const DEFAULT_SECRET_KEY = [
  "sb",
  "secret",
  "default",
  "a".repeat(20),
].join("_");
const WORKFLOW_SECRET_KEY = [
  "sb",
  "secret",
  "workflow",
  "a".repeat(20),
].join("_");

function claim(
  overrides: Partial<ExploreMediaHealthClaim> = {},
): ExploreMediaHealthClaim {
  return {
    media_id: "media-1",
    post_id: "post-1",
    user_id: "user-1",
    kind: "image",
    url: "https://media.merian.app/public_uploads/pro/user-1/image.webp",
    thumbnail_url:
      "https://media.merian.app/public_uploads/pro/user-1/image.webp",
    health_status: "healthy",
    claim_token: "claim-1",
    ...overrides,
  };
}

Deno.test("inspectExploreMediaClaim treats a direct R2 404 as missing", async () => {
  const result = await inspectExploreMediaClaim(
    claim(),
    R2_CONFIG,
    () => Promise.resolve(new Response(null, { status: 404 })),
  );

  assertEquals(result, {
    outcome: "missing",
    urlHttpStatus: 404,
    thumbnailHttpStatus: 404,
  });
});

Deno.test("inspectExploreMediaClaim treats R2 5xx as retryable", async () => {
  const result = await inspectExploreMediaClaim(
    claim(),
    R2_CONFIG,
    () => Promise.resolve(new Response(null, { status: 503 })),
  );

  assertEquals(result.outcome, "retryable_error");
  assertEquals(result.urlHttpStatus, 503);
});

Deno.test("inspectExploreMediaClaim rejects another owner's durable key", async () => {
  await assertRejects(
    () =>
      inspectExploreMediaClaim(
        claim({
          url: "https://media.merian.app/public_uploads/pro/user-2/image.webp",
        }),
        R2_CONFIG,
        () => Promise.resolve(new Response(null, { status: 200 })),
      ),
    Error,
    "not canonical durable media for its owner",
  );
});

Deno.test("inspectExploreMediaClaim records a missing poster without hiding the video", async () => {
  const keys: string[] = [];
  const result = await inspectExploreMediaClaim(
    claim({
      kind: "video",
      thumbnail_url:
        "https://media.merian.app/public_uploads/pro/user-1/poster.webp",
    }),
    R2_CONFIG,
    (key) => {
      keys.push(key);
      const status = key.endsWith("poster.webp") ? 404 : 200;
      return Promise.resolve(new Response(null, { status }));
    },
  );

  assertEquals(keys.length, 2);
  assertEquals(result.outcome, "healthy");
  assertEquals(result.urlHttpStatus, 200);
  assertEquals(result.thumbnailHttpStatus, 404);
});

Deno.test("reconcileExploreMediaHealth records every leased outcome", async () => {
  const records: Array<Record<string, unknown>> = [];
  const runs: ExploreMediaHealthRunInsert[] = [];
  const result = await reconcileExploreMediaHealth({} as never, {
    now: new Date("2026-07-26T12:00:00.000Z"),
  }, {
    r2Config: R2_CONFIG,
    claimChecks: () => Promise.resolve([claim()]),
    headObject: () => Promise.resolve(new Response(null, { status: 200 })),
    recordCheck: (
      leasedClaim,
      outcome,
      urlHttpStatus,
      thumbnailHttpStatus,
    ) => {
      records.push({
        mediaId: leasedClaim.media_id,
        outcome,
        urlHttpStatus,
        thumbnailHttpStatus,
      });
      return Promise.resolve();
    },
    recordRun: (run) => {
      runs.push(run);
      return Promise.resolve();
    },
  });

  assertEquals(result.healthy, 1);
  assertEquals(result.errorCount, 0);
  assertEquals(result.omittedErrors, 0);
  assertEquals(result.errors, []);
  assertEquals(records, [{
    mediaId: "media-1",
    outcome: "healthy",
    urlHttpStatus: 200,
    thumbnailHttpStatus: 200,
  }]);
  assertEquals(runs.length, 1);
});

Deno.test("reconcileExploreMediaHealth audits a batch-claim failure", async () => {
  const runs: ExploreMediaHealthRunInsert[] = [];

  await assertRejects(
    () =>
      reconcileExploreMediaHealth({} as never, {
        now: new Date("2026-07-26T12:00:00.000Z"),
      }, {
        r2Config: R2_CONFIG,
        claimChecks: () => Promise.reject(new Error("database unavailable")),
        recordRun: (run) => {
          runs.push(run);
          return Promise.resolve();
        },
      }),
    Error,
    "database unavailable",
  );

  assertEquals(runs.length, 1);
  assertEquals(runs[0].status, "failed");
  assertEquals(runs[0].errors, [{ reason: "claim_failed" }]);
});

Deno.test("handler accepts an exact configured project secret", async () => {
  let acceptedToken = "";
  let receivedOptions: unknown;
  const result = {
    claimed: 0,
    healthy: 0,
    missingObservations: 0,
    retryableErrors: 0,
    errorCount: 0,
    omittedErrors: 0,
    errors: [],
  };
  const handler = createReconcileExploreMediaHealthHandler({
    supabaseUrl: "https://project.supabase.co",
    envSecretKeys: JSON.stringify({
      default: DEFAULT_SECRET_KEY,
      workflow: WORKFLOW_SECRET_KEY,
    }),
    createAdminClient: (_supabaseUrl, token) => {
      acceptedToken = token;
      return {} as never;
    },
    reconcile: (_supabaseAdmin, options) => {
      receivedOptions = options;
      return Promise.resolve(result);
    },
  });

  const response = await handler(
    new Request(
      "https://project.supabase.co/functions/v1/reconcile-explore-media-health",
      {
        method: "POST",
        headers: {
          apikey: WORKFLOW_SECRET_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ limit: 1, leaseSeconds: 300 }),
      },
    ),
  );

  assertEquals(response.status, 200);
  assertEquals(acceptedToken, WORKFLOW_SECRET_KEY);
  assertEquals(receivedOptions, { limit: 1, leaseSeconds: 300 });
  assertEquals(await response.json(), { success: true, ...result });
});

Deno.test("handler rejects an unconfigured public project key", async () => {
  let createdAdminClient = false;
  const handler = createReconcileExploreMediaHealthHandler({
    supabaseUrl: "https://project.supabase.co",
    envSecretKeys: JSON.stringify({
      workflow: WORKFLOW_SECRET_KEY,
    }),
    createAdminClient: () => {
      createdAdminClient = true;
      return {} as never;
    },
  });

  const response = await handler(
    new Request(
      "https://project.supabase.co/functions/v1/reconcile-explore-media-health",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer unprivileged-key",
          apikey: "unprivileged-key",
        },
      },
    ),
  );

  assertEquals(response.status, 401);
  assertEquals(createdAdminClient, false);
});
