import { serve } from "@std/http/server.ts";
import { createClient } from "@supabase/supabase-js";
import { requireAuth } from "../_shared/auth.ts";
import { getS3Client } from "../_shared/aws.ts";
import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

serve(async (req: Request) => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user, response } = await requireAuth(req, supabaseAdmin);
    if (response) return response;

    const body = await req.json();
    const { fileNames } = body;
    const userId = user!.id;

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
    const aws = getS3Client();

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
