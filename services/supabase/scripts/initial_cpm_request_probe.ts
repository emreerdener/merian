/** Offline child of the owned disposable CPM qualification. The parent keeps the
 * prepared provider parameters in memory and passes them back only after a committed
 * original SQL grant. Never load a credential, contact a provider or save media. */
import { readInitialRecoveryHttp } from "../functions/check-scan-status/initialRecovery.ts";
import { isDeepStrictEqual } from "node:util";
import { syntheticOriginalPhotoSnapshot as snapshot } from "../functions/_shared/initialAnalysis/fixtures/cpmPhotoExecutionRequest.ts";
import { identificationProvenance } from "../functions/_shared/ai/provenance.ts";
import { identificationUsageFacts } from "../functions/_shared/ai/identificationUsage.ts";
import { decodeBase64, encodeBase64 } from "../functions/_shared/encoding.ts";

import { createInitialCpmPhotoRequestPreparer } from "../functions/_shared/initialAnalysis/cpmPhotoExecutionRequest.ts";
import { initialCanonicalText } from "../functions/_shared/initialAnalysis/canonical.ts";
import { captureInitialResult } from "../functions/_shared/initialAnalysis/resultEvidence.ts";
import { data } from "../functions/_shared/initialAnalysis/fixtures/resultEvidence.ts";
import {
  initialMediaHash,
  mediaUUID,
} from "../functions/_shared/initialAnalysis/mediaBinding.ts";
import { readInitialStream } from "../functions/_shared/initialAnalysis/transport.ts";

const signal = AbortSignal.timeout(15000);
const input = JSON.parse(
  new TextDecoder("utf-8", { fatal: true }).decode(
    await readInitialStream(Deno.stdin.readable, 262144, signal),
  ),
);
const encode = (s: string) => new TextEncoder().encode(s);
if (Deno.args[0] === "prepare") {
  const a = JSON.parse(input.original.assignment_canonical);
  const { role_mapping, ...policy } = a.preparation;
  // Explicit synthetic fixture profile, independent of live model selection.
  const prepare = createInitialCpmPhotoRequestPreparer({
    configurationCanonical: initialCanonicalText(a.configuration),
    preparationPolicyCanonical: initialCanonicalText(policy),
    verification: input.policy,
    snapshot,
  });
  const photos = role_mapping.filter((m: { role: string }) => m.role === "ai")
    .map((m: { object_id: string }, index: number) => ({
      objectID: m.object_id,
      bytes: decodeBase64(input.syntheticAI[index]),
    }));
  const packet = await prepare(input.original, input.ack, photos, signal);
  console.log(
    JSON.stringify({
      ...packet,
      provenance: identificationProvenance(packet.snapshot),
      parametersDigest: await initialMediaHash(encode(packet.parameters)),
    }),
  );
} else if (Deno.args[0] === "synthetic-result") {
  const { packet, grant } = input;
  if (
    grant.version !== 1 || grant.outcome !== "fresh" ||
    !mediaUUID(grant.invocation_id) ||
    await initialMediaHash(encode(packet.parameters)) !==
      packet.parametersDigest
  ) throw new Error("original grant or parameters mismatch");
  const projection = {
    ...data(),
    scan_id: packet.binding.scan_id,
    inference_tier: "pro",
    identification_provenance: identificationProvenance(packet.snapshot),
  };
  // The executable database fixture has no provider client. The SDK wire
  // projection of this same preparer is checked by cpmPhotoExecutionRequest_test.
  const params = JSON.parse(packet.parameters);
  const parts = params.contents?.[0]?.parts;
  if (
    params.model !== packet.snapshot.model || !Array.isArray(parts) ||
    parts.length !== input.expectedAI.length + 1 ||
    parts.at(-1).text !==
      "Observation-wide supporting descriptions (JSON):\n" +
        JSON.stringify(input.contexts)
  ) {
    throw new Error("synthetic receiver input mismatch");
  }
  for (const [i, digest] of input.expectedAI.entries()) {
    const image = parts[i].inlineData;
    if (
      image.mimeType !== "image/jpeg" ||
      await initialMediaHash(decodeBase64(image.data).slice()) !== digest
    ) {
      throw new Error("synthetic receiver image mismatch");
    }
  }
  const syntheticReply = JSON.stringify(projection);
  const outcome = {
    kind: "draft" as const,
    draft: JSON.parse(syntheticReply),
    execution: { ...packet.snapshot, durationMs: 1 },
    providerDurationMs: 1,
    providerCompletedAt: 1000,
    returnedModel: packet.snapshot.model,
    usage: {
      promptTokens: 101,
      candidateTokens: 37,
      totalTokens: 138,
      thinkingTokens: null,
      cachedTokens: null,
      modalityBreakdown: {},
    },
    finishReason: "STOP",
    responseCharacters: syntheticReply.length,
  };
  const evidence = await captureInitialResult({
    binding: packet.binding,
    invocationId: grant.invocation_id,
    resultEvidenceId: crypto.randomUUID(),
    outcome,
    data: outcome.draft,
  });
  console.log(
    JSON.stringify({
      evidence,
      usage: identificationUsageFacts(outcome),
      syntheticCalls: 1,
    }),
  );
} else if (Deno.args[0] === "deliver") {
  const admission = JSON.parse(input.admission);
  let reads = 0;
  const http = await readInitialRecoveryHttp(
    new Request("http://127.0.0.1/check-scan-status", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-merian-initial-recovery": "completion-v1",
      },
      body: JSON.stringify({
        initial_recovery: {
          version: 1,
          phase: "completion",
          original: admission,
        },
      }),
      signal,
    }),
    admission.owner_id,
    {
      origin: "http://127.0.0.1",
      serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
      fetcher: (url, init) => {
        const args = JSON.parse(String(init?.body));
        if (
          ++reads !== 1 ||
          String(url) !==
            "http://127.0.0.1/rest/v1/rpc/discover_initial_completion_v1" ||
          !isDeepStrictEqual(args, {
            p_owner: admission.owner_id,
            p_scan: admission.scan_id,
            p_admission: input.admission,
          })
        ) throw new Error("unexpected completion read");
        return Promise.resolve(Response.json(input.reply));
      },
    },
  );
  if (http.status !== 200 || http.headers.get("cache-control") !== "no-store") {
    throw new Error("original HTTP recovery refused");
  }
  const response = new Uint8Array(await http.arrayBuffer());
  const status = JSON.parse(new TextDecoder().decode(response));
  if (
    status.outcome !== input.outcome ||
    status.admission_canonical !== input.admission
  ) throw new Error("original status mismatch");
  if (
    input.outcome === "found" &&
    (status.result_canonical !== input.result.result_canonical ||
      status.result_digest !== input.result.result_digest ||
      status.original_provenance_canonical !==
        input.result.provenance_canonical ||
      status.reference_canonical !==
        initialCanonicalText(input.result.reference))
  ) throw new Error("stored result mismatch");
  console.log(
    JSON.stringify({
      outcome: status.outcome,
      reads,
      ...(Deno.args[1] === "--public-wire"
        ? { body_base64: encodeBase64(response) }
        : {}),
      byteCount: response.length,
      sha256: await initialMediaHash(response.slice()),
    }),
  );
} else throw new Error("unknown disposable probe phase");
