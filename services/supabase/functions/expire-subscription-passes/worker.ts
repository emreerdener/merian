import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { migrateUserStorage } from "../_shared/storageMigration.ts";
import {
  downgradeExpiredSubscriptionPass,
  fetchExpiredSubscriptionPassUsers,
} from "./db.ts";

export interface ExpireSubscriptionPassesResult {
  scanned: number;
  downgraded: number;
}

type StorageMigrator = (
  userId: string,
  sourcePrefix: string,
  targetPrefix: string,
  supabaseAdmin: SupabaseClient,
) => Promise<void>;

interface ExpireSubscriptionPassesDependencies {
  fetchExpiredUsers?: typeof fetchExpiredSubscriptionPassUsers;
  downgradeUser?: typeof downgradeExpiredSubscriptionPass;
  storageMigrator?: StorageMigrator;
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
  const storageMigrator = dependencies.storageMigrator ?? migrateUserStorage;
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
    await storageMigrator(user.id, "pro", "free", supabaseAdmin);
  }

  return {
    scanned: users.length,
    downgraded,
  };
}
