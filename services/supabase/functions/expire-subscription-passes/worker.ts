import { SupabaseClient } from "@supabase/supabase-js";
import {
  downgradeExpiredSubscriptionPass,
  fetchExpiredSubscriptionPassUsers,
} from "./db.ts";

export interface ExpireSubscriptionPassesResult {
  scanned: number;
  downgraded: number;
}

interface ExpireSubscriptionPassesDependencies {
  fetchExpiredUsers?: typeof fetchExpiredSubscriptionPassUsers;
  downgradeUser?: typeof downgradeExpiredSubscriptionPass;
}

export async function processExpiredSubscriptionPasses(
  supabaseAdmin: SupabaseClient,
  now = new Date(),
  dependencies: ExpireSubscriptionPassesDependencies = {},
): Promise<ExpireSubscriptionPassesResult> {
  const fetchExpiredUsers = dependencies.fetchExpiredUsers ??
    fetchExpiredSubscriptionPassUsers;
  const downgradeUser = dependencies.downgradeUser ??
    downgradeExpiredSubscriptionPass;
  const boundaryIso = now.toISOString();
  const users = await fetchExpiredUsers(boundaryIso, supabaseAdmin);
  let downgraded = 0;

  for (const user of users) {
    const didDowngrade = await downgradeUser(
      user.id,
      boundaryIso,
      supabaseAdmin,
    );
    if (!didDowngrade) continue;
    downgraded++;
  }

  return {
    scanned: users.length,
    downgraded,
  };
}
