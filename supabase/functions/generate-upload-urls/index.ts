import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.17";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { userId, imageCount } = await req.json();

    if (!userId || typeof imageCount !== "number") {
      throw new Error(
        "Invalid request payload. Expected userId and imageCount.",
      );
    }

    // Limit to max 5 images per request
    const count = Math.min(imageCount, 5);

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

    const endpoint = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com`;

    const uploadUrls: Record<number, string> = {};
    const destinationUrls: Record<number, string> = {};

    for (let i = 0; i < count; i++) {
      // Generate random UUID using crypto
      const imageId = crypto.randomUUID();
      // Construct strict quarantine path
      const key = `quarantine/${userId}/${imageId}.jpg`;
      const urlString = `${endpoint}/${R2_BUCKET_NAME}/${key}`;

      // 1. Generate Signed PUT URL (Expires in 900 seconds)
      const putUrl = new URL(urlString);
      putUrl.searchParams.set("X-Amz-Expires", "900");
      const signedPut = await aws.sign(putUrl, {
        method: "PUT",
        aws: { signQuery: true },
      });
      uploadUrls[i] = signedPut.url;

      // 2. Generate Signed GET URL (Expires in 3600 seconds)
      const getUrl = new URL(urlString);
      getUrl.searchParams.set("X-Amz-Expires", "3600");
      const signedGet = await aws.sign(getUrl, {
        method: "GET",
        aws: { signQuery: true },
      });
      destinationUrls[i] = signedGet.url;
    }

    return new Response(JSON.stringify({ uploadUrls, destinationUrls }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
