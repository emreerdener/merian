import { AwsClient } from "aws4fetch";

export function getS3Client(): AwsClient {
    return new AwsClient({
        accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID") || "",
        secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY") || "",
        region: "auto",
    });
}

export function getR2Config() {
    const accountId = Deno.env.get("R2_ACCOUNT_ID") ?? "";
    const bucketName = Deno.env.get("R2_BUCKET_NAME") ?? "";
    const endpoint = `https://${accountId}.r2.cloudflarestorage.com`;
    return {
        s3Client: getS3Client(),
        bucketName,
        endpoint
    };
}
