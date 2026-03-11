import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
// createClient included to instantiate Admin client for DB connections
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { AwsClient } from "https://esm.sh/aws4fetch@1.0.17";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// Admin client not needed here.

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { fileNames, user_id } = await req.json();

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      );
    }

    // 1. Validate the JWT utilizing the Anon Key + Injected Auth Header natively
    const supabaseAuthClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      { global: { headers: { Authorization: authHeader } } }
    );

    const {
      data: { user },
      error: authError,
    } = await supabaseAuthClient.auth.getUser();

    if (authError || !user) {
      console.error("Auth Rejection:", authError);
      return new Response(
        JSON.stringify({ error: "Invalid or expired Session" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 401 }
      );
    }

    if (!user_id) {
       return new Response(
           JSON.stringify({ error: "Missing user_id parameter in body" }), 
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
    const urls: { fileName: string; signedUrl: string; objectKey: string }[] =
      [];

    for (const fileName of fileNames) {
      const imageId = crypto.randomUUID();
      const key = `staging/${user_id}/${imageId}.jpg`;
      const urlString = `${endpoint}/${R2_BUCKET_NAME}/${key}`;

      const putUrl = new URL(urlString);
      putUrl.searchParams.set("X-Amz-Expires", "86400");

      const signedPut = await aws.sign(putUrl.toString(), {
        method: "PUT",
        headers: { "Content-Type": "image/jpeg" },
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
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
