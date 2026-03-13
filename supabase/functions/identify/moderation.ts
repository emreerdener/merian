import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";

export async function evaluateAndProcessPayload(
  userId: string,
  r2ObjectKey: string,
  geminiFinishReason: string | undefined,
  // deno-lint-ignore no-explicit-any
  safetyRatings: any[] | undefined,
  userTier: string,
): Promise<{ status: string; publicUrl?: string }> {
  try {
    // 1. Evaluate Gemini Safety Ratings and Finish Reason
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

    // 2. Initialize Core Clients
    const R2_ACCOUNT_ID = Deno.env.get("R2_ACCOUNT_ID")!;
    const R2_BUCKET_NAME = Deno.env.get("R2_BUCKET_NAME")!;
    const R2_ACCESS_KEY_ID = Deno.env.get("R2_ACCESS_KEY_ID")!;
    const R2_SECRET_ACCESS_KEY = Deno.env.get("R2_SECRET_ACCESS_KEY")!;

    const aws = new AwsClient({
      accessKeyId: R2_ACCESS_KEY_ID,
      secretAccessKey: R2_SECRET_ACCESS_KEY,
      service: "s3",
      region: "auto",
    });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    // Service role key is required to patch user abuse_strikes reliably
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const tier = userTier === "pro" ? "pro" : "free";

    const endpoint = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;
    const fileName = r2ObjectKey.split("/").pop();
    const publicUploadKey = `public_uploads/${tier}/${userId}/${fileName}`;

    const stagingUrl = `${endpoint}/${R2_BUCKET_NAME}/${r2ObjectKey}`;
    const publicUrl = `${endpoint}/${R2_BUCKET_NAME}/${publicUploadKey}`;

    // 3. Unsafe Flow Pipeline
    if (isUnsafe) {
      console.warn(
        `Unsafe media detected for user ${userId}. Engaging Unsafe Flow.`,
      );

      // Step A: Send DELETE request purging image explicitly from staging
      const deleteReq = new Request(stagingUrl, { method: "DELETE" });
      const signedDelete = await aws.sign(deleteReq);
      await fetch(signedDelete);

      // Step B: Fetch and increment abuse strikes in Supabase
      const { data: userData, error: fetchError } = await supabase
        .from("users")
        .select("abuse_strikes")
        .eq("id", userId)
        .single();

      if (fetchError && fetchError.code !== "PGRST116") {
        console.error(
          `Failed to fetch user profiles for safety escalation. Error:`,
          fetchError,
        );
      }

      const currentStrikes = userData?.abuse_strikes ?? 0;
      const updatedStrikes = currentStrikes + 1;
      const isShadowbanned = updatedStrikes >= 3;

      // Step C: Update penalty counters
      const { error: updateError } = await supabase
        .from("users")
        .update({
          abuse_strikes: updatedStrikes,
          is_shadowbanned: isShadowbanned,
        })
        .eq("id", userId);

      if (updateError) {
        console.error(`Failed to update user bounds. Error:`, updateError);
      }

      return { status: isShadowbanned ? "SHADOWBANNED" : "DELETED_WARNING" };
    }

    // 4. Safe Flow Pipeline
    console.log(`Media marked safe. Engaing Safe Flow Pipeline.`);

    // Step A: Copy source image structurally within R2
    const copyReq = new Request(publicUrl, {
      method: "PUT",
      headers: {
        "x-amz-copy-source": `/${R2_BUCKET_NAME}/${r2ObjectKey}`,
      },
    });

    const signedCopy = await aws.sign(copyReq);
    const copyRes = await fetch(signedCopy);

    if (copyRes.ok) {
      // Step B: Purge origin from staging payload block after valid internal transfer
      const originDeleteReq = new Request(stagingUrl, { method: "DELETE" });
      const signedOriginDelete = await aws.sign(originDeleteReq);
      await fetch(signedOriginDelete);
    } else {
      console.error(`Failed to promote payload into R2. Pipeline stopped.`);
    }

    return { status: "PROMOTED", publicUrl };
  } catch (error) {
    console.error(`Moderation Pipeline Critical Failure:`, error);
    return { status: "ERROR" };
  }
}
