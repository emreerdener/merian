import { AwsClient } from "aws4fetch";
import { type FixtureID, FIXTURES, validAlias } from "./policy.ts";
/** Signing only. Never AwsClient.fetch (its retry policy is excluded). */
export function privateGetAdapter(options: {
  endpoint: string;
  bucket: string;
  run: string;
  accessKeyId: string;
  secretAccessKey: string;
  fetchOnce(request: Request): Promise<Response>;
}) {
  const url = new URL(options.endpoint);
  if (
    url.protocol !== "https:" ||
    !/^[a-f0-9]{32}\.r2\.cloudflarestorage\.com$/.test(url.hostname) ||
    url.port || url.username || url.password || url.search || url.hash ||
    url.pathname !== "/" || options.bucket !== "merian-cpm-verifier-fixtures" ||
    !validAlias(options.run) || !options.accessKeyId || !options.secretAccessKey
  ) throw Error("private_get_config");
  const signer = new AwsClient({
    accessKeyId: options.accessKeyId,
    secretAccessKey: options.secretAccessKey,
    region: "auto",
    service: "s3",
    retries: 0,
  });
  const origin = url.origin,
    bucket = options.bucket,
    run = options.run,
    fetchOnce = options.fetchOnce;
  return async (fixture: FixtureID, signal: AbortSignal) => {
    if (!Object.hasOwn(FIXTURES, fixture)) throw Error("fixture");
    signal.throwIfAborted();
    const request = await signer.sign(
      new Request(
        `${origin}/${bucket}/cpm-verifier/${run}/${FIXTURES[fixture].key}`,
        { method: "GET", redirect: "error", signal },
      ),
    );
    signal.throwIfAborted();
    return await fetchOnce(new Request(request, { signal, redirect: "error" }));
  };
}
