import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { getR2Config } from "../_shared/aws.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, _supabaseAdmin) => {
    const { fileNames } = await req.json();

    if (!user.id) {
      return jsonResponse({ error: "Unauthorized: Missing identity context." }, 401);
    }

    // Explicitly protect the Cloudflare R2 staging environment from spam loops
    // by restricting batch queues strictly to 5 high-res chunks natively.
    if (!Array.isArray(fileNames) || fileNames.length === 0 || fileNames.length > 5) {
      return jsonResponse({
        error: "Bad Request: 'fileNames' must be an array of 1 to 5 values."
      }, 400);
    }

    const { s3Client, bucketName, endpoint } = getR2Config();

    // Fan-out cryptographic pre-signed URL mappings symmetrically
    const urls = await Promise.all(
      fileNames.map(async (fileName: string) => {
        const imageId = crypto.randomUUID();
        const key = `staging/${user.id}/${imageId}.jpg`;
        const urlString = `${endpoint}/${bucketName}/${key}`;

        const putUrl = new URL(urlString);

        // Lock AWS expiration natively to 24 hours (86400 seconds)
        putUrl.searchParams.set("X-Amz-Expires", "86400");

        const signedPut = await s3Client.sign(putUrl.toString(), {
          method: "PUT",
          headers: { "Content-Type": "image/jpeg" },
          aws: { signQuery: true }
        });

        return {
          fileName,
          signedUrl: signedPut.url,
          objectKey: key
        };
      })
    );

    return jsonResponse({
      success: true,
      urls
    }, 200);
  })
);
