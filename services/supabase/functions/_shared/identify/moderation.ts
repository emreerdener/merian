import { createClient } from "@supabase/supabase-js";
import { SafetyRating } from "@google/genai";

import { copyR2Object, deleteR2Object, getR2Config } from "../aws.ts";
import { logStructuredError } from "../edgeHandler.ts";
import { decodeBase64 } from "../encoding.ts";

type PromotionR2Config = ReturnType<typeof getR2Config>;

interface PromotionDependencies {
  copyObject?: typeof copyR2Object;
  deleteObject?: typeof deleteR2Object;
  fetchImpl?: typeof fetch;
  signRequest?: (request: Request) => Promise<Request>;
}

interface PromoteSafeMediaInput {
  userId: string;
  r2ObjectKeys: string[] | undefined;
  imageBase64s: string[] | undefined;
  userTier: string;
  r2Config: PromotionR2Config;
  contentType?: string;
  fallbackExtension?: string;
}

function publicUrlForKey(key: string): string {
  return `https://media.merian.app/${key}`;
}

export async function promoteSafeMedia(
  {
    userId,
    r2ObjectKeys,
    imageBase64s,
    userTier,
    r2Config,
    contentType = "image/webp",
    fallbackExtension = "webp",
  }: PromoteSafeMediaInput,
  {
    copyObject = copyR2Object,
    deleteObject = deleteR2Object,
    fetchImpl = fetch,
    signRequest = async (request: Request) =>
      await r2Config.s3Client.sign(request),
  }: PromotionDependencies = {},
): Promise<string[]> {
  const tier = userTier === "pro" ? "pro" : "free";
  const { bucketName, endpoint } = r2Config;
  const promotedKeys: string[] = [];

  try {
    if (imageBase64s && imageBase64s.length > 0) {
      let index = 0;
      for (const base64 of imageBase64s) {
        const fallbackUUID = crypto.randomUUID();
        const fileName = r2ObjectKeys?.[index]?.split("/").pop() ||
          `${fallbackUUID}.${fallbackExtension}`;
        const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;
        const targetS3Url = `${endpoint}/${bucketName}/${publicUploadKey}`;

        const arrayBuffer = decodeBase64(base64);
        const uploadReq = new Request(targetS3Url, {
          method: "PUT",
          headers: { "Content-Type": contentType },
          body: arrayBuffer as unknown as BodyInit,
        });
        const signedUpload = await signRequest(uploadReq);
        const uploadRes = await fetchImpl(signedUpload);
        if (!uploadRes.ok) {
          throw new Error(
            `Failed to upload base64 image to R2: ${uploadRes.status} ${uploadRes.statusText}`,
          );
        }
        promotedKeys.push(publicUploadKey);
        index++;
      }
    } else if (r2ObjectKeys && r2ObjectKeys.length > 0) {
      for (const r2Key of r2ObjectKeys) {
        const fileName = r2Key.split("/").pop();
        const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;

        const copyRes = await copyObject(r2Key, publicUploadKey, r2Config);
        if (!copyRes.ok) {
          throw new Error(
            `Failed to promote staging image to public storage: ${r2Key}`,
          );
        }

        promotedKeys.push(publicUploadKey);
        await deleteObject(r2Key, r2Config);
      }
    }

    return promotedKeys.map(publicUrlForKey);
  } catch (error) {
    if (promotedKeys.length > 0) {
      const rollbackResults = await Promise.allSettled(
        promotedKeys.map((key) => deleteObject(key, r2Config)),
      );
      const failedRollbacks = rollbackResults.filter((result) =>
        result.status === "rejected"
      );
      if (failedRollbacks.length > 0) {
        logStructuredError("moderation/rollback_partial_failure", {
          userId,
          failed_count: failedRollbacks.length,
          total_count: promotedKeys.length,
          original_error: error instanceof Error
            ? error.message
            : String(error),
        });
      }
    }
    throw error;
  }
}

export async function evaluateAndProcessPayload(
  userId: string,
  r2ObjectKeys: string[] | undefined,
  imageBase64s: string[] | undefined,
  geminiFinishReason: string | undefined,
  safetyRatings: SafetyRating[] | undefined,
  userTier: string,
  additionalStagedKeysToDeleteOnUnsafe: string[] = [],
): Promise<{ status: string; publicUrls?: string[] }> {
  try {
    // 1. Evaluate Gemini safety ratings
    let isUnsafe = false;

    if (geminiFinishReason === "SAFETY") {
      isUnsafe = true;
    } else if (safetyRatings && Array.isArray(safetyRatings)) {
      for (const rating of safetyRatings) {
        if (rating.probability === "MEDIUM" || rating.probability === "HIGH") {
          isUnsafe = true;
          break;
        }
      }
    }

    const r2Config = getR2Config();
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    // 2. Unsafe flow — purge staging image and escalate abuse strike
    if (isUnsafe) {
      console.warn(`Unsafe media detected for user ${userId}.`);

      const stagedKeysToDelete = [
        ...((!imageBase64s || imageBase64s.length === 0) ? r2ObjectKeys ?? [] : []),
        ...additionalStagedKeysToDeleteOnUnsafe,
      ];
      if (stagedKeysToDelete.length > 0) {
        await Promise.allSettled(
          stagedKeysToDelete.map((key) => deleteR2Object(key, r2Config)),
        );
      }

      const { data: userData, error: fetchError } = await supabase
        .from("users")
        .select("abuse_strikes")
        .eq("id", userId)
        .single();

      if (fetchError && fetchError.code !== "PGRST116") {
        logStructuredError("moderation/strike_fetch_failed", {
          userId,
          error: fetchError.message,
        });
        throw new Error(`Abuse strike fetch failed: ${fetchError.message}`);
      }

      const currentStrikes = userData?.abuse_strikes ?? 0;
      const updatedStrikes = currentStrikes + 1;
      const isShadowbanned = updatedStrikes >= 3;

      const { error: updateError } = await supabase
        .from("users")
        .update({
          abuse_strikes: updatedStrikes,
          is_shadowbanned: isShadowbanned,
        })
        .eq("id", userId);

      if (updateError) {
        logStructuredError("moderation/strike_write_failed", {
          userId,
          error: updateError.message,
        });
        throw new Error(`Abuse strike write failed: ${updateError.message}`);
      }

      return {
        status: isShadowbanned ? "SHADOWBANNED" : "DELETED_WARNING",
      };
    }

    // 3. Safe flow — promote image to public storage
    console.log(`Media safe for user ${userId}. Engaging safe flow pipeline.`);
    const publicUrls = await promoteSafeMedia({
      userId,
      r2ObjectKeys,
      imageBase64s,
      userTier,
      r2Config,
    });

    return { status: "PROMOTED", publicUrls };
  } catch (error) {
    logStructuredError("moderation/pipeline_error", {
      userId,
      error: error instanceof Error ? error.message : String(error),
    });
    return { status: "ERROR" };
  }
}
