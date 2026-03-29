import { getR2Config, generatePresignedPutUrl } from "../_shared/aws.ts";

export interface PresignedUrlPayload {
  fileName: string;
  signedUrl: string;
  objectKey: string;
}

export async function generateStagingUrls(
  userId: string,
  fileNames: string[],
): Promise<PresignedUrlPayload[]> {
  const r2Config = getR2Config();

  const urls = await Promise.all(
    fileNames.map(async (fileName: string) => {
      // Sanitize fileName to prevent directory traversal
      const safeFileName = fileName.replace(/[^a-zA-Z0-9_.-]/g, "_");
      const key = `staging/${userId}/${safeFileName}`;

      return {
        fileName,
        signedUrl: await generatePresignedPutUrl(r2Config, key),
        objectKey: key,
      };
    }),
  );

  return urls;
}
