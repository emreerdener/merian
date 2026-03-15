import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";
import * as jose from "https://deno.land/x/jose@v5.2.2/index.ts";

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
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      );
    }

    // Explicitly strip the 'Bearer ' prefix to prevent "Bearer Bearer <token>" extraction bugs
    const token = authHeader.replace(/^Bearer\s+/i, '').trim()

    // Validate the ES256 token locally to eliminate round-trip latency
    let user: { id: string };
    try {
      const jwtSecret = Deno.env.get("SUPABASE_JWT_SECRET")!;
      const secretKey = new TextEncoder().encode(jwtSecret);
      const { payload } = await jose.jwtVerify(token, secretKey);
      if (!payload.sub) throw new Error("No subject");
      user = { id: payload.sub };
    } catch (e) {
      console.error("Local Auth Rejection:", e);
      return new Response(JSON.stringify({ error: "Invalid or expired Session" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } })
    }

    const body = await req.json();
    const { fileNames } = body;
    const userId = user.id;

    if (!userId) {
       return new Response(
           JSON.stringify({ error: "Missing identity token" }), 
           { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
       );
    }

    if (
      !Array.isArray(fileNames) ||
      fileNames.length === 0 ||
      fileNames.length > 5
    ) {
      throw new Error("Invalid request or exceeded maximum files.");
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
    const urls = await Promise.all(
      fileNames.map(async (fileName: string) => {
        const imageId = crypto.randomUUID();
        const key = `staging/${userId}/${imageId}.jpg`;
        const urlString = `${endpoint}/${R2_BUCKET_NAME}/${key}`;

        const putUrl = new URL(urlString);
        putUrl.searchParams.set("X-Amz-Expires", "86400");

        const signedPut = await aws.sign(putUrl.toString(), {
          method: "PUT",
          headers: { "Content-Type": "image/jpeg" },
          aws: { signQuery: true },
        });

        return {
          fileName: fileName,
          signedUrl: signedPut.url,
          objectKey: key,
        };
      })
    );

    return new Response(JSON.stringify({ urls }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
