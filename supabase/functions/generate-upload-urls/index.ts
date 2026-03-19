import { serve } from "@std/http/server.ts";
import { getR2Config } from "../_shared/aws.ts";
import { withEdgeHandler, jsonResponse } from "../_shared/edgeHandler.ts";

serve((req: Request) => withEdgeHandler(req, async (user, _supabaseAdmin) => {
    const body = await req.json();
    const { fileNames } = body;
    const userId = user.id;

    if (!userId) {
       return jsonResponse({ error: "Missing identity token" }, 400);
    }

    if (
      !Array.isArray(fileNames) ||
      fileNames.length === 0 ||
      fileNames.length > 5
    ) {
      throw new Error("Invalid request or exceeded maximum files.");
    }

    const { s3Client, bucketName, endpoint } = getR2Config();

    const urls = await Promise.all(
      fileNames.map(async (fileName: string) => {
        const imageId = crypto.randomUUID();
        const key = `staging/${userId}/${imageId}.jpg`;
        const urlString = `${endpoint}/${bucketName}/${key}`;

        const putUrl = new URL(urlString);
        putUrl.searchParams.set("X-Amz-Expires", "86400");

        const signedPut = await s3Client.sign(putUrl.toString(), {
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

    return jsonResponse({ urls });
}));
