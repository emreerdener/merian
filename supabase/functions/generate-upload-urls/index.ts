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
    const { fileNames } = await req.json();

    if (!Array.isArray(fileNames) || fileNames.length === 0) {
      throw new Error("Invalid request payload. Expected fileNames array.");
    }

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
    const urls: { fileName: string; signedUrl: string; objectKey: string }[] =
      [];

    for (const fileName of fileNames) {
      const imageId = crypto.randomUUID();
      const key = `staging/${imageId}_${fileName}`;
      const urlString = `${endpoint}/${R2_BUCKET_NAME}/${key}`;

      const putUrl = new URL(urlString);
      putUrl.searchParams.set("X-Amz-Expires", "900");

      const signedPut = await aws.sign(putUrl, {
        method: "PUT",
        aws: { signQuery: true },
      });

      urls.push({
        fileName: fileName,
        signedUrl: signedPut.url,
        objectKey: key,
      });
    }

    return new Response(JSON.stringify({ urls }), {
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
