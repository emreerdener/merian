import { AwsClient } from "https://esm.sh/aws4fetch@1.0.20";

export interface R2Config {
  s3Client: AwsClient;
  bucketName: string;
  endpoint: string;
}

export function getS3Client(): AwsClient {
  return new AwsClient({
    accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID") ?? "",
    secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY") ?? "",
    region: "auto"
  });
}

export function getR2Config(): R2Config {
  const accountId = Deno.env.get("R2_ACCOUNT_ID") ?? "";
  const bucketName = Deno.env.get("R2_BUCKET_NAME") ?? "";
  const endpoint = `https://${accountId}.r2.cloudflarestorage.com`;
  
  return {
    s3Client: getS3Client(),
    bucketName,
    endpoint
  };
}

export function getInternalS3Url(publicUrl: string, config: R2Config): string {
  return publicUrl.replace("https://media.merian.app/", `${config.endpoint}/${config.bucketName}/`);
}

export const deleteR2Objects = async (urls: string[], r2Config: R2Config) => {
  const { s3Client } = r2Config;
  await Promise.allSettled(
    urls.map(async (url: string) => {
      try {
        console.log(`Obliterating R2 payload: ${url}`);
        const s3Url = getInternalS3Url(url, r2Config);
        await s3Client.fetch(s3Url, { method: "DELETE" });
      } catch (e) {
        console.error(`Failed to wipe media at ${url} from Cloudflare R2:`, e);
      }
    })
  );
};

export async function copyR2Object(sourceKey: string, targetKey: string, config: R2Config): Promise<Response> {
  const { s3Client, bucketName, endpoint } = config;
  const copyUrl = `${endpoint}/${bucketName}/${targetKey}`;
  
  return await s3Client.fetch(copyUrl, {
    method: "PUT",
    headers: {
      "x-amz-copy-source": encodeURI(`/${bucketName}/${sourceKey}`)
    }
  });
}

export async function deleteR2Object(key: string, config: R2Config): Promise<Response> {
  const { s3Client, bucketName, endpoint } = config;
  const deleteUrl = `${endpoint}/${bucketName}/${key}`;
  return await s3Client.fetch(deleteUrl, { method: "DELETE" });
}
