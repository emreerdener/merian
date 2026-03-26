import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getR2Config } from "../_shared/aws.ts";
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

    const { s3Client, bucketName, endpoint } = getR2Config();

    const urls = await Promise.all(
      fileNames.map(async (fileName: string) => {
        // Sanitize fileName to prevent directory traversal
        const safeFileName = fileName.replace(/[^a-zA-Z0-9_.-]/g, "_");
        const key = `staging/${user.id}/${safeFileName}`;
        const urlString = `${endpoint}/${bucketName}/${key}`;

        const putUrl = new URL(urlString);
        putUrl.searchParams.set("X-Amz-Expires", "86400"); // 24-hour expiration

        const signedPut = await s3Client.sign(putUrl.toString(), {
          method: "PUT",
          headers: { "Content-Type": "image/webp" },
          aws: { signQuery: true }
        });

        return {
          fileName,
          signedUrl: signedPut.url,
          objectKey: key
        };
      })
    );

    return jsonResponse({ success: true, urls }, 200);
  })
);
