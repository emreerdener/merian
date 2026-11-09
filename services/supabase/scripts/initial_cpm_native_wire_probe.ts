/** Offline projection child for a synthetic native/disposable SQL join.
 * Private SQL replies arrive on stdin and never leave this process. Only the
 * existing public HTTP response bytes, length and digest go to the parent. */
import { isDeepStrictEqual } from "node:util";
import { initialPhotoAllocation } from "../functions/initial-photo-allocation/handler.ts";
import { readInitialRecoveryHttp } from "../functions/check-scan-status/initialRecovery.ts";
import { readInitialStream } from "../functions/_shared/initialAnalysis/transport.ts";
import { initialMediaHash } from "../functions/_shared/initialAnalysis/mediaBinding.ts";
import { encodeBase64 } from "../functions/_shared/encoding.ts";

const signal = AbortSignal.timeout(15000);
const input = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(
  await readInitialStream(Deno.stdin.readable, 524288, signal),
));
let reads = 0;
let http: Response;
if (Deno.args[0] === "allocation") {
  const body = {
    version: 3,
    action: "create",
    candidate_canonical: input.candidate,
  };
  http = await initialPhotoAllocation(
    new Request("http://127.0.0.1/initial-photo-allocation", {
      method: "POST",
      signal,
    }),
    body,
    input.owner,
    {
      call: (owner, request) => {
        if (
          ++reads !== 1 || owner !== input.owner ||
          request.candidateCanonical !== input.candidate ||
          request.version !== 3 || request.action !== "create"
        ) {
          throw new Error("fixture allocation binding");
        }
        return Promise.resolve(input.reply);
      },
    },
  );
} else if (Deno.args[0] === "admission") {
  const original = input.original;
  http = await readInitialRecoveryHttp(
    new Request("http://127.0.0.1/check-scan-status", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-merian-initial-recovery": "admission-v1",
      },
      body: JSON.stringify({
        initial_recovery: { version: 1, phase: "admission", original },
      }),
      signal,
    }),
    original.owner_id,
    {
      origin: "http://127.0.0.1",
      serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
      fetcher: (url, init) => {
        if (
          ++reads !== 1 || String(url) !==
            "http://127.0.0.1/rest/v1/rpc/read_initial_cpm_saved_admission_v1" ||
          !isDeepStrictEqual(JSON.parse(String(init?.body)), {
            p_owner: original.owner_id,
            p_scan: original.scan_id,
            p_candidate: original.candidate_canonical,
            p_candidate_digest: original.candidate_digest,
            p_content_digest: original.content_digest,
            p_assignment_digest: original.assignment_digest,
            p_backend_generation: original.backend_generation,
            p_backend_configuration_digest:
              original.backend_configuration_digest,
          })
        ) throw new Error("fixture admission binding");
        return Promise.resolve(Response.json(input.reply));
      },
    },
  );
} else throw new Error("fixture projection mode");
if (
  http.status !== 200 ||
  !http.headers.get("cache-control")?.includes("no-store")
) {
  throw new Error("fixture public projection refused");
}
const bytes = new Uint8Array(await http.arrayBuffer());
if (
  Deno.args[0] === "admission" &&
  !isDeepStrictEqual(
    JSON.parse(new TextDecoder().decode(bytes)),
    input.acknowledgement,
  )
) {
  throw new Error("fixture original admission changed");
}
console.log(JSON.stringify({
  body_base64: encodeBase64(bytes),
  byteCount: bytes.length,
  sha256: await initialMediaHash(bytes.slice()),
  reads,
}));
