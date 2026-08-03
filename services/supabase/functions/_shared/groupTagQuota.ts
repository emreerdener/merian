import type { SupabaseClient, User } from "@supabase/supabase-js";
import {
  type AIProviderQuotaLease,
  deriveAIRequestId,
  reserveAIProviderCall,
} from "./aiQuota.ts";
import { fetchGroupTags } from "./biology.ts";
import { logStructuredError } from "./edgeHandler.ts";

/**
 * Runs optional group-tag inference behind its own quota reservation.
 *
 * Group tags are background enrichment, so quota exhaustion or provider
 * failure must not discard an otherwise successful identification. The
 * reservation is still committed before the provider is invoked; a failed
 * provider attempt becomes retryable without refunding cost/rate counters.
 */
export async function fetchQuotaGuardedGroupTags(
  req: Request,
  user: User,
  scientificName: string,
  supabaseAdmin: SupabaseClient,
  parentRequestId: string,
): Promise<Awaited<ReturnType<typeof fetchGroupTags>>> {
  let quotaLease: AIProviderQuotaLease | null = null;
  let providerAttempted = false;

  try {
    const requestId = await deriveAIRequestId(
      parentRequestId,
      "scan_group_tag_enrichment",
    );
    quotaLease = await reserveAIProviderCall(req, supabaseAdmin, {
      userId: user.id,
      operation: "scan_group_tag_enrichment",
      requestId,
      originalAnalysisId: parentRequestId,
    });
    await quotaLease.commit();
    providerAttempted = true;

    const result = await fetchGroupTags(
      user,
      scientificName,
      quotaLease.reservation.model,
      supabaseAdmin,
    );
    if (!result) await quotaLease.fail();
    return result;
  } catch (error) {
    if (quotaLease) {
      if (providerAttempted) {
        await quotaLease.fail();
      } else {
        await quotaLease.refund();
      }
    }
    logStructuredError("group_tags/quota_or_provider_failed", {
      error_code: error instanceof Error && "code" in error
        ? String(error.code)
        : "unknown",
    });
    return null;
  }
}
