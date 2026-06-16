import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { copyR2Object, deleteR2Object, getR2Config } from "./aws.ts";

export interface StorageMigrationDependencies {
  getR2Config?: typeof getR2Config;
  copyR2Object?: typeof copyR2Object;
  deleteR2Object?: typeof deleteR2Object;
}

export async function migrateUserStorage(
  userId: string,
  sourcePrefix: string,
  targetPrefix: string,
  supabaseAdmin: SupabaseClient,
  dependencies: StorageMigrationDependencies = {},
) {
  try {
    const resolveR2Config = dependencies.getR2Config ?? getR2Config;
    const copyObject = dependencies.copyR2Object ?? copyR2Object;
    const deleteObject = dependencies.deleteR2Object ?? deleteR2Object;
    let totalMigrated = 0;
    let hasMore = true;
    let start = 0;
    const pageSize = 1000;

    while (hasMore) {
      const { data: scans, error: scansError } = await supabaseAdmin
        .from("scans")
        .select("id, image_storage_urls")
        .eq("user_id", userId)
        .order("id", { ascending: true })
        .range(start, start + pageSize - 1);

      if (scansError) throw scansError;

      if (!scans || scans.length === 0) {
        hasMore = false;
        break;
      }

      const BATCH_SIZE = 50;
      for (let i = 0; i < scans.length; i += BATCH_SIZE) {
        const chunk = scans.slice(i, i + BATCH_SIZE);

        await Promise.allSettled(
          chunk.map(async (scan) => {
            if (
              !scan.image_storage_urls ||
              scan.image_storage_urls.length === 0
            ) {
              return;
            }

            let migrated = false;

            const urlPromises = scan.image_storage_urls.map(
              async (urlStr: string) => {
                if (urlStr.includes(`public_uploads/${targetPrefix}/`)) {
                  return urlStr;
                }

                if (urlStr.includes(`public_uploads/${sourcePrefix}/`)) {
                  const parsedUrl = new URL(urlStr);
                  const pathParts = parsedUrl.pathname.split("/");
                  const fileName = pathParts.pop();
                  const originalUserId = pathParts.pop();

                  if (originalUserId !== userId) {
                    console.warn(
                      `IDOR: User ${userId} attempted to migrate asset owned by ${originalUserId}.`,
                    );
                    return urlStr;
                  }

                  const sourceKey =
                    `public_uploads/${sourcePrefix}/${originalUserId}/${fileName}`;
                  const targetKey =
                    `public_uploads/${targetPrefix}/${userId}/${fileName}`;

                  const r2Config = resolveR2Config();
                  const copyResponse = await copyObject(
                    sourceKey,
                    targetKey,
                    r2Config,
                  );

                  if (copyResponse.ok) {
                    await deleteObject(sourceKey, r2Config);
                    totalMigrated++;
                    migrated = true;
                    return `https://media.merian.app/${targetKey}`;
                  }

                  console.error(
                    `R2 copy failed for ${sourceKey}: ${copyResponse.statusText}`,
                  );
                  return `https://media.merian.app/${sourceKey}`;
                }

                return urlStr;
              },
            );

            const resolvedUrls = await Promise.all(urlPromises);

            if (migrated) {
              await supabaseAdmin
                .from("scans")
                .update({ image_storage_urls: resolvedUrls })
                .eq("id", scan.id);
            }
          }),
        );
      }

      if (scans.length < pageSize) {
        hasMore = false;
      } else {
        start += pageSize;
      }
    }

    console.log(
      `Storage migration complete: ${totalMigrated} objects moved from ${sourcePrefix} to ${targetPrefix} for user ${userId}.`,
    );
  } catch (e) {
    console.error(
      `Storage migration (${sourcePrefix} -> ${targetPrefix}) failed for user ${userId}:`,
      e,
    );
  }
}
