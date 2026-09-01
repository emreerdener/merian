import { assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { PublicHttpError } from "../_shared/http.ts";
import {
  isLegacyCommunityPostReport,
  resolveLegacyCommunityPostReport,
  submitOwnedFlagIssue,
} from "./db.ts";

interface FlagIssueClientOptions {
  ownedResult?: unknown;
  ownedError?: { message: string } | null;
  request?: { id?: unknown; post_id?: unknown } | null;
  requestError?: { message: string } | null;
  detail?: unknown;
  detailError?: { message: string } | null;
  rpcCalls?: Array<{ name: string; args: Record<string, unknown> }>;
}

function flagIssueClient(options: FlagIssueClientOptions): SupabaseClient {
  return {
    from(table: string) {
      assertEquals(table, "explore_community_requests");
      return {
        select(columns: string) {
          assertEquals(columns, "id,post_id");
          return {
            eq(column: string, value: string) {
              assertEquals(column, "scan_id");
              assertEquals(value, scanId);
              return {
                is(nullColumn: string, nullValue: null) {
                  assertEquals(nullColumn, "withdrawn_at");
                  assertEquals(nullValue, null);
                  return {
                    maybeSingle: () =>
                      Promise.resolve({
                        data: options.request ?? null,
                        error: options.requestError ?? null,
                      }),
                  };
                },
              };
            },
          };
        },
      };
    },
    rpc(name: string, args: Record<string, unknown>) {
      options.rpcCalls?.push({ name, args });
      if (name === "submit_owned_flag_issue") {
        return Promise.resolve({
          data: options.ownedResult,
          error: options.ownedError ?? null,
        });
      }
      assertEquals(name, "get_community_identification_detail");
      return Promise.resolve({
        data: options.detail ?? [],
        error: options.detailError ?? null,
      });
    },
  } as unknown as SupabaseClient;
}

const scanId = "00000000-0000-4000-8000-000000000101";
const reporterId = "00000000-0000-4000-8000-000000000102";
const requestId = "00000000-0000-4000-8000-000000000103";
const postId = "00000000-0000-4000-8000-000000000104";

Deno.test("owned flag issue uses the atomic service RPC", async () => {
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const result = await submitOwnedFlagIssue(
    scanId,
    reporterId,
    "Incorrect species",
    "Expected suggestion",
    flagIssueClient({ ownedResult: "submitted", rpcCalls }),
  );

  assertEquals(result, "submitted");
  assertEquals(rpcCalls, [{
    name: "submit_owned_flag_issue",
    args: {
      p_scan_id: scanId,
      p_reporter_user_id: reporterId,
      p_flag_reason: "Incorrect species",
      p_user_suggestion: "Expected suggestion",
    },
  }]);
});

Deno.test("owned flag issue preserves non-owner and unavailable results", async () => {
  for (const expected of ["not_owner", "not_found"] as const) {
    const result = await submitOwnedFlagIssue(
      scanId,
      reporterId,
      "Other",
      undefined,
      flagIssueClient({ ownedResult: expected }),
    );
    assertEquals(result, expected);
  }
});

Deno.test("owned flag issue fails closed on database and result errors", async () => {
  await assertRejects(
    () =>
      submitOwnedFlagIssue(
        scanId,
        reporterId,
        "Other",
        undefined,
        flagIssueClient({
          ownedResult: null,
          ownedError: { message: "scan lookup unavailable" },
        }),
      ),
    Error,
    "Failed to submit flagged review",
  );
  await assertRejects(
    () =>
      submitOwnedFlagIssue(
        scanId,
        reporterId,
        "Other",
        undefined,
        flagIssueClient({ ownedResult: "unexpected" }),
      ),
    Error,
    "invalid result",
  );
});

Deno.test("legacy Community post-report fingerprint is exact", () => {
  assertEquals(
    isLegacyCommunityPostReport(
      "Inappropriate content",
      "Reported from Community request",
    ),
    true,
  );
  assertEquals(
    isLegacyCommunityPostReport(
      "Incorrect species",
      "Reported from Community request",
    ),
    false,
  );
  assertEquals(
    isLegacyCommunityPostReport("Inappropriate content", undefined),
    false,
  );
});

Deno.test("legacy Community post report resolves one visible exact post", async () => {
  const rpcCalls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const target = await resolveLegacyCommunityPostReport(
    scanId,
    reporterId,
    flagIssueClient({
      request: { id: requestId, post_id: postId },
      detail: [{
        scan_id: scanId.toUpperCase(),
        post_id: postId.toUpperCase(),
      }],
      rpcCalls,
    }),
  );

  assertEquals(target, { postId });
  assertEquals(rpcCalls, [{
    name: "get_community_identification_detail",
    args: {
      self_id: reporterId,
      target_request_id: requestId,
    },
  }]);
});

Deno.test("legacy Community post report rejects missing and mismatched context", async () => {
  await assertRejects(
    () =>
      resolveLegacyCommunityPostReport(
        scanId,
        reporterId,
        flagIssueClient({ request: null }),
      ),
    PublicHttpError,
    "not available for reporting",
  );
  await assertRejects(
    () =>
      resolveLegacyCommunityPostReport(
        scanId,
        reporterId,
        flagIssueClient({
          request: { id: requestId, post_id: postId },
          detail: [{
            scan_id: "00000000-0000-4000-8000-000000000999",
            post_id: postId,
          }],
        }),
      ),
    PublicHttpError,
    "not available for reporting",
  );
  await assertRejects(
    () =>
      resolveLegacyCommunityPostReport(
        scanId,
        reporterId,
        flagIssueClient({
          request: { id: requestId, post_id: postId },
          detail: [{
            scan_id: scanId,
            post_id: "00000000-0000-4000-8000-000000000999",
          }],
        }),
      ),
    PublicHttpError,
    "not available for reporting",
  );
});

Deno.test("legacy Community post report fails closed on request lookup error", async () => {
  await assertRejects(
    () =>
      resolveLegacyCommunityPostReport(
        scanId,
        reporterId,
        flagIssueClient({
          requestError: { message: "request lookup unavailable" },
        }),
      ),
    Error,
    "Failed to resolve legacy Community post report",
  );
});

Deno.test("legacy Community post report fails closed on visibility RPC error", async () => {
  await assertRejects(
    () =>
      resolveLegacyCommunityPostReport(
        scanId,
        reporterId,
        flagIssueClient({
          request: { id: requestId, post_id: postId },
          detailError: { message: "detail unavailable" },
        }),
      ),
    Error,
    "Failed to authorize legacy Community post report",
  );
});
