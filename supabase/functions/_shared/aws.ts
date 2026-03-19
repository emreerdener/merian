import { AwsClient } from "aws4fetch";

export function getS3Client(): AwsClient {
    return new AwsClient({
        accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID") || "",
        secretAccessKey: Deno.env.get("R2_SECRET_ACCESS_KEY") || "",
        region: "auto",
    });
}
