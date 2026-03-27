import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getR2Config, generatePresignedPutUrl } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, _supabaseAdmin) => {
    const { fileNames } = await req.json();

    // Limit uploads to 5 files per request to prevent R2 abuse
    if (!Array.isArray(fileNames) || fileNames.length === 0 || fileNames.length > 5) {
      return jsonResponse({
        error: "Bad Request: 'fileNames' must be an array of 1 to 5 values."
      }, 400);
    }

    const r2Config = getR2Config();

    const urls = await Promise.all(
      fileNames.map(async (fileName: string) => {
        // Sanitize fileName to prevent directory traversal
        const safeFileName = fileName.replace(/[^a-zA-Z0-9_.-]/g, "_");
        const key = `staging/${user.id}/${safeFileName}`;
        return {
          fileName,
          signedUrl: await generatePresignedPutUrl(r2Config, key),
          objectKey: key,
        };
      })
    );

    return jsonResponse({ success: true, urls }, 200);
  })
);
