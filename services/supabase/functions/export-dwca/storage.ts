import JSZip from "jszip";
import { getR2Config } from "../_shared/aws.ts";

export async function zipAndUploadToR2(
  occurrenceCsv: string,
  multimediaCsv: string,
  metaXml: string,
  userId: string,
): Promise<string> {
  const zip = new JSZip();
  zip.file("occurrence.csv", occurrenceCsv);
  zip.file("multimedia.csv", multimediaCsv);
  zip.file("meta.xml", metaXml);

  const zipStream = zip.generateInternalStream({
    type: "uint8array",
    compression: "STORE",
  });

  const readableZipStream = new ReadableStream({
    start(controller) {
      zipStream.on("data", (data: Uint8Array) => controller.enqueue(data))
        .on("end", () => controller.close())
        .on("error", (err: Error) => controller.error(err));
      zipStream.resume();
    },
  });

  const { s3Client, bucketName, endpoint } = getR2Config();
  const timestamp = Date.now();
  const exportKey = `exports/${userId}/Scans_DwC_Archive_${timestamp}.zip`;
  const urlString = `${endpoint}/${bucketName}/${exportKey}`;

  const putRes = await s3Client.fetch(urlString, {
    method: "PUT",
    headers: { "Content-Type": "application/zip" },
    body: readableZipStream,
  });

  if (!putRes.ok) {
    throw new Error(`Failed to upload to R2: ${putRes.statusText}`);
  }

  const getUrl = new URL(urlString);
  getUrl.searchParams.set("X-Amz-Expires", "86400"); // 24 hours

  const signedGet = await s3Client.sign(getUrl.toString(), {
    method: "GET",
    aws: { signQuery: true },
  });

  return signedGet.url;
}
