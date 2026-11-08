import {
  binding,
  capture,
  data,
  id,
  other,
  outcome,
  snapshot,
} from "./fixtures/resultEvidence.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { AIQuotaReservation } from "../aiQuota.ts";
import { prepareInitialAccountedIdentification } from "./dispatchAccounting.ts";
import { assert, assertEquals, assertRejects, assertThrows } from "@std/assert";
import { identificationProvenance } from "../ai/provenance.ts";
import { identifyWireEnvelopeContract } from "../identify/contract.ts";
import { initialCanonicalText, initialDecimal } from "./canonical.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import { transformInitialResult } from "./resultEncoding.ts";
import {
  type CapturedInitialResult,
  captureInitialResult,
  decodeInitialResult,
  persistInitialResult,
} from "./resultEvidence.ts";

function decode(value: CapturedInitialResult, original = value) {
  return decodeInitialResult(
    value,
    original.reference,
    original.provenance_canonical,
  );
}
const hash = (text: string) =>
  initialMediaHash(
    new TextEncoder().encode(`merian.initial-analysis.result.v1\n${text}`),
  );
Deno.test("initial capture retains exact validated values, usage and original invocation with decimal encoding", async () => {
  const original = data();
  const evidence = await capture(original);
  assert(Object.isFrozen(evidence) && Object.isFrozen(evidence.reference));
  const encoded = JSON.parse(evidence.result_canonical);
  assertEquals(encoded.data.confidence_score, "0.87");
  assertEquals(encoded.data.estimated_size_cm, "8.5");
  assertEquals(encoded.data.image_quality.sharpness, 8);
  assertEquals(encoded.data.pet_identification, null);
  assertEquals(Object.hasOwn(encoded.data, "taxonomy"), false);
  assertEquals(encoded.invocation_id, id);
  assertEquals(encoded.provider_usage.input_tokens, null);
  assertEquals(encoded.provider_usage.modality_breakdown, {});
  assertEquals(evidence.result_digest, await hash(evidence.result_canonical));
  assertEquals(await decode(evidence), original);
  assertEquals(evidence.result_canonical.includes("unvalidated"), false);
});
Deno.test("initial capture snapshots synchronously before digest awaits and recovery is immutable", async () => {
  const original = data();
  const pending = capture(original);
  original.common_name = "later edit";
  (original.extracted_visual_traits as string[]).push("later trait");
  const evidence = await pending;
  const recovered = await decode(evidence);
  assertEquals(recovered.common_name, "Monarch Butterfly");
  assertEquals(recovered.extracted_visual_traits, ["synthetic wings"]);
  assert(
    Object.isFrozen(recovered) &&
      Object.isFrozen(recovered.extracted_visual_traits),
  );
});
for (
  const [name, mutate] of Object.entries<
    ((value: Record<string, unknown>) => void)
  >({
    unknown: (v) => {
      v.unrecognized = true;
    },
    missing_provenance: (v) => {
      delete v.identification_provenance;
    },
    wrong_scan: (v) => {
      v.scan_id = other;
    },
    bad_range: (v) => {
      v.confidence_score = 1.01;
    },
    negative_zero: (v) => {
      v.blur_score = -0;
    },
    nan: (v) => {
      v.confidence_score = NaN;
    },
    null_required: (v) => {
      v.ai_reasoning = null;
    },
    nul: (v) => {
      v.ai_reasoning = "a\0b";
    },
    surrogate: (v) => {
      v.ai_reasoning = "\ud800";
    },
    provenance_mismatch: (v) => {
      v.identification_provenance = {
        ...identificationProvenance(snapshot),
        model: "different-model",
      };
    },
  })
) {
  Deno.test(`initial result rejects ${name} before durable write`, async () => {
    const original = data();
    mutate(original);
    await assertRejects(() => capture(original));
  });
}
Deno.test("initial codec does not invoke accessors, toJSON or accept sparse evidence arrays", async () => {
  let accesses = 0;
  const original = data();
  Object.defineProperty(original, "confidence_score", {
    enumerable: true,
    get() {
      accesses++;
      return 0.87;
    },
  });
  await assertRejects(() => capture(original));
  assertEquals(accesses, 0);
  await assertRejects(() =>
    capture({
      ...data(),
      toJSON() {
        accesses++;
        return data();
      },
    })
  );
  assertEquals(accesses, 0);
  const sparse = data();
  sparse.extracted_visual_traits = new Array(2);
  await assertRejects(() => capture(sparse));
});
Deno.test("initial result requires a successful parsed result rather than refusal or raw draft", async () => {
  await assertRejects(() => capture(outcome.draft));
  await assertRejects(() =>
    captureInitialResult({
      binding,
      invocationId: id,
      resultEvidenceId: other,
      outcome: { ...outcome, kind: "refusal" },
      data: data(),
    })
  );
});
Deno.test("initial fractional codec round trips finite boundary values without exponents", () => {
  const rule = { kind: "number", minimum: -1, maximum: 1 } as const;
  for (
    const value of [0, 0.1, 1, -1, Number.MIN_VALUE, -Number.MIN_VALUE, 1e-7]
  ) {
    const encoded = transformInitialResult(rule, value, "encode");
    assertEquals(encoded, initialDecimal(value));
    assertEquals(transformInitialResult(rule, encoded, "decode"), value);
  }
  for (
    const text of [
      "-0",
      "-0.0",
      "1e-7",
      "0.10",
      "0.100000000000000005",
      "0." + "0".repeat(323) + "4",
      " 0.1",
      "1.01",
    ]
  ) {
    assertThrows(() => transformInitialResult(rule, text, "decode"));
  }
});
Deno.test("initial recovery rejects altered identities, digest, provenance and non-round-trip decimal even if rehashed", async () => {
  const original = await capture();
  await assertRejects(() =>
    decode({
      ...original,
      reference: { ...original.reference, result_evidence_id: id },
    }, original)
  );
  await assertRejects(() =>
    decode({ ...original, result_digest: "f".repeat(64) }, original)
  );
  await assertRejects(() =>
    decodeInitialResult(original, original.reference, "{}")
  );
  const altered = JSON.parse(original.result_canonical);
  altered.data.confidence_score = "0.87000000000000000001";
  const text = initialCanonicalText(altered);
  const alteredDigest = await hash(text);
  await assertRejects(() =>
    decode({
      ...original,
      result_canonical: text,
      result_digest: alteredDigest,
    }, original)
  );
});
Deno.test("initial recovery rejects cross-field primary semantic violations", async () => {
  const original = data();
  original.primary_identification = {
    version: 1,
    resolution: "species",
    scientific_name: "Danaus plexippus",
    common_name: "Monarch Butterfly",
  };
  await assertRejects(() => capture(original));
  assertEquals(
    identifyWireEnvelopeContract.fields.data.contract.kind,
    "object",
  );
});
Deno.test("lost result write acknowledgement reconciles exact durable evidence without a second write", async () => {
  const original = await capture();
  let writes = 0, reads = 0;
  const status = await persistInitialResult(
    {
      write: () => {
        writes++;
        return Promise.reject(new Error("synthetic lost ack"));
      },
      read: (requested) => {
        reads++;
        assertEquals(requested.result_digest, original.result_digest);
        assertEquals(
          requested.result_evidence_id,
          original.reference.result_evidence_id,
        );
        return Promise.resolve({ ...original });
      },
    },
    original,
    new AbortController().signal,
  );
  assertEquals(status, "stored");
  assertEquals(writes, 1);
  assertEquals(reads, 1);
});
for (const mode of ["absent", "mismatch", "read_error"] as const) {
  Deno.test(`result write ${mode} remains held with no provider or promotion path`, async () => {
    const original = await capture();
    let writes = 0, reads = 0;
    const status = await persistInitialResult(
      {
        write: () => {
          writes++;
          return Promise.resolve();
        },
        read: () => {
          reads++;
          if (mode === "read_error") {
            return Promise.reject(new Error("synthetic read failure"));
          }
          return Promise.resolve(
            mode === "absent" ? null : {
              ...original,
              reference: { ...original.reference, invocation_id: other },
            },
          );
        },
      },
      original,
      new AbortController().signal,
    );
    assertEquals(status, "held");
    assertEquals(writes, 1);
    assertEquals(reads, 1);
  });
}
Deno.test("untrusted copied evidence cannot enter result writer; cancelled caller cannot write", async () => {
  const original = await capture();
  let calls = 0;
  const store = {
    write: () => {
      calls++;
      return Promise.resolve();
    },
    read: () => {
      calls++;
      return Promise.resolve(original);
    },
  };
  await assertRejects(() =>
    persistInitialResult(store, { ...original }, new AbortController().signal)
  );
  const caller = new AbortController();
  caller.abort();
  assertEquals(
    await persistInitialResult(store, original, caller.signal),
    "held",
  );
  assertEquals(calls, 0);
});

Deno.test("original dispatch through result persistence survives usage loss and write acknowledgement loss", async () => {
  let providers = 0, reports = 0, writes = 0, reads = 0;
  const prepared = prepareInitialAccountedIdentification({
    client: {
      rpc() {
        throw new Error("ordinary RPC forbidden");
      },
    } as unknown as SupabaseClient,
    reservation: {
      id,
      leaseToken: id,
      requestId: id,
      attemptCount: 1,
    } as AIQuotaReservation,
    execution: {
      snapshot,
      invoke: () => {
        providers++;
        return Promise.resolve(outcome);
      },
    },
    binding,
    executionEvidence: initialCanonicalText({
      version: 1,
      synthetic_verifier_proof: true,
    }),
    origin: "https://project.supabase.co",
    serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
    caller: new AbortController().signal,
    fetcher: (url) => {
      if (String(url).endsWith("authorize_initial_analysis_dispatch")) {
        return Promise.resolve(Response.json({
          version: 1,
          owner_id: id,
          scan_id: id,
          submission_digest: binding.submission_digest,
          admission_receipt_id: id,
          admission_receipt_digest: binding.admission_receipt_digest,
          outcome: "fresh",
          invocation_id: id,
        }));
      }
      reports++;
      return Promise.reject(new Error("synthetic lost usage report"));
    },
  });
  const original = await prepared.invoke();
  const evidence = await captureInitialResult({
    binding,
    invocationId: original.invocationId,
    resultEvidenceId: other,
    outcome: original.outcome,
    data: data(),
  });
  let durable: CapturedInitialResult | null = null;
  const stored = await persistInitialResult(
    {
      write: (value) => {
        writes++;
        durable = { ...value };
        return Promise.reject(new Error("synthetic lost commit reply"));
      },
      read: () => {
        reads++;
        return Promise.resolve(durable);
      },
    },
    evidence,
    new AbortController().signal,
  );
  assertEquals(stored, "stored");
  assertEquals({ providers, reports, writes, reads }, {
    providers: 1,
    reports: 1,
    writes: 1,
    reads: 1,
  });
  assertEquals((await decode(evidence)).scan_id, id);
  await assertRejects(() => prepared.invoke());
});
