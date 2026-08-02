import { assertEquals, assertStringIncludes } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { deleteMergedGhostAuthUser } from "../merge-ghost-profile/db.ts";
import type { GhostMergeCleanupClaim } from "./db.ts";
import { reconcileGhostProfileMerges } from "./worker.ts";

const CLAIMS: GhostMergeCleanupClaim[] = [
  {
    handoffId: "00000000-0000-0000-0000-000000000701",
    ghostUserId: "00000000-0000-0000-0000-000000000711",
    targetUserId: "00000000-0000-0000-0000-000000000721",
    claimToken: "00000000-0000-0000-0000-000000000731",
  },
  {
    handoffId: "00000000-0000-0000-0000-000000000702",
    ghostUserId: "00000000-0000-0000-0000-000000000712",
    targetUserId: "00000000-0000-0000-0000-000000000722",
    claimToken: "00000000-0000-0000-0000-000000000732",
  },
];

Deno.test("ghost merge reconciler records successful and retryable Auth cleanup outcomes", async () => {
  const finished: Array<{
    handoffId: string;
    succeeded: boolean;
    errorCode: string | null;
  }> = [];

  const result = await reconcileGhostProfileMerges(
    {} as SupabaseClient,
    500,
    {
      claim: (_client, limit) => {
        assertEquals(limit, 100);
        return Promise.resolve(CLAIMS);
      },
      deleteAuthUser: (ghostUserId) =>
        Promise.resolve(
          ghostUserId === CLAIMS[0].ghostUserId
            ? { succeeded: true as const }
            : {
              succeeded: false as const,
              errorCode: "auth_http_503",
            },
        ),
      finish: (_client, claim, succeeded, errorCode) => {
        finished.push({
          handoffId: claim.handoffId,
          succeeded,
          errorCode,
        });
        return Promise.resolve();
      },
    },
  );

  assertEquals(result.claimed, 2);
  assertEquals(result.deleted, 1);
  assertEquals(result.failed, 1);
  assertEquals(result.errors[0]?.reason, "auth_http_503");
  assertEquals(finished, [
    {
      handoffId: CLAIMS[0].handoffId,
      succeeded: true,
      errorCode: null,
    },
    {
      handoffId: CLAIMS[1].handoffId,
      succeeded: false,
      errorCode: "auth_http_503",
    },
  ]);
});

Deno.test("ghost Auth deletion treats only 404 or user_not_found as idempotent success", async () => {
  const adminFor = (error: unknown) =>
    ({
      auth: {
        admin: {
          deleteUser: () => Promise.resolve({ data: null, error }),
        },
      },
    }) as unknown as SupabaseClient;

  assertEquals(
    await deleteMergedGhostAuthUser(
      CLAIMS[0].ghostUserId,
      adminFor({ status: 404, message: "missing" }),
    ),
    { succeeded: true },
  );
  assertEquals(
    await deleteMergedGhostAuthUser(
      CLAIMS[0].ghostUserId,
      adminFor({
        status: 422,
        code: "user_not_found",
        message: "missing",
      }),
    ),
    { succeeded: true },
  );

  const unrelated = await deleteMergedGhostAuthUser(
    CLAIMS[0].ghostUserId,
    adminFor({
      status: 500,
      code: "database_error",
      message: "related object not found",
    }),
  );
  assertEquals(unrelated.succeeded, false);
  if (!unrelated.succeeded) {
    assertStringIncludes(unrelated.errorCode, "database_error");
  }
});
