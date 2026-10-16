import {
  assert,
  assertEquals,
  assertNotEquals,
  assertRejects,
} from "@std/assert";
import { initialCanonicalText as canon } from "./canonical.ts";
import {
  MEDIA_HANDOFF_PROOF_LIMITS,
  mediaHandoffProofDigest,
  type MediaHandoffProofKind,
  validateMediaTransferReceipt,
  validateMediaVerificationClaim,
  validateMediaVerificationReceipt,
} from "./mediaHandoffProof.ts";
import admitted from "./fixtures/admitted-proof-v1.json" with { type: "json" };
import vectors from "./fixtures/media-handoff-proof-v1.json" with {
  type: "json",
};
import schema from "./media-handoff-proof-schema-v1.json" with { type: "json" };
import metadataSchema from "./admission-metadata-schema-v1.json" with {
  type: "json",
};

function fixture(index = 0) {
  const v = structuredClone(vectors.valid[index]);
  return {
    v,
    original: structuredClone(
      admitted.valid[v.admitted_vector_index].components,
    ),
  };
}
const otherID = "ffffffff-ffff-ffff-ffff-ffffffffffff";
const otherDigest = "f".repeat(64);
async function rechain(v: ReturnType<typeof fixture>["v"]) {
  v.claim_digest = await mediaHandoffProofDigest("claim", canon(v.claim));
  v.verification_receipt.claim = structuredClone(v.claim);
  v.verification_receipt.claim_digest = v.claim_digest;
  v.verification_receipt_digest = await mediaHandoffProofDigest(
    "verification_receipt",
    canon(v.verification_receipt),
  );
  v.transfer_receipt.verification_receipt = structuredClone(
    v.verification_receipt,
  );
  v.transfer_receipt.verification_receipt_digest =
    v.verification_receipt_digest;
}
function transfer(original: unknown, v: ReturnType<typeof fixture>["v"]) {
  return validateMediaTransferReceipt(
    original,
    v.claim,
    v.verification_receipt,
    v.transfer_receipt,
  );
}

Deno.test("media handoff: all original photo/audio/video cohorts match independent digests without authority", async () => {
  for (const vector of vectors.valid) {
    const { original, v } = fixture(vector.admitted_vector_index);
    for (
      const [actual, value, expected] of [
        [
          await validateMediaVerificationClaim(original, v.claim),
          v.claim,
          v.claim_digest,
        ],
        [
          await validateMediaVerificationReceipt(
            original,
            v.claim,
            v.verification_receipt,
          ),
          v.verification_receipt,
          v.verification_receipt_digest,
        ],
        [
          await transfer(original, v),
          v.transfer_receipt,
          v.transfer_receipt_digest,
        ],
      ] as const
    ) {
      assertEquals(actual, {
        authority: "none",
        canonical: canon(value),
        digest: expected,
      });
    }
  }
  assertEquals(schema.claim.properties.binding, metadataSchema.media_binding);
  assertEquals(schema.verification_receipt.properties.claim, schema.claim);
  assertEquals(
    schema.transfer_receipt.properties.verification_receipt,
    schema.verification_receipt,
  );
  assertEquals(MEDIA_HANDOFF_PROOF_LIMITS, {
    claim: 32768,
    verification_receipt: 65536,
    transfer_receipt: 98304,
  });
});

Deno.test("media handoff: admitted original is fully verified, never just a supplied digest", async () => {
  const { original, v } = fixture();
  await assertRejects(() =>
    transfer({ receiptDigest: v.claim.admission_receipt_digest }, v)
  );
  for (const key of Object.keys(original) as (keyof typeof original)[]) {
    await assertRejects(() => transfer({ ...original, [key]: "{}" }, v));
  }
  await assertRejects(() => transfer(fixture(2).original, v));
  const bad = structuredClone(v);
  bad.claim.admission_receipt_digest = otherDigest;
  bad.transfer_receipt.admission_receipt_digest = otherDigest;
  await rechain(bad);
  await assertRejects(() => transfer(original, bad));
});

Deno.test("media handoff: changed original binding and adapter fail even with recomputed nested digests", async () => {
  for (
    const edit of [
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.binding.owner_id = otherID;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.binding.scan_id = otherID;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.binding.admission_receipt_id = otherID;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.binding.assignment_digest = otherDigest;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.binding.mapping_digest = otherDigest;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.binding.phase_window.cutoffs.verification += 1;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.verification_adapter_digest = otherDigest;
      },
    ]
  ) {
    const { original, v } = fixture();
    edit(v);
    await rechain(v);
    await assertRejects(() => transfer(original, v));
  }
});

Deno.test("media handoff: complete ordered union rejects missing, extra, alias, backend and byte changes", async () => {
  const edits = [
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x.pop();
    },
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x.push(structuredClone(x[0]));
    },
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x.reverse();
    },
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x[0].object_id = otherID;
    },
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x[0].backend_generation = otherID;
    },
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x[0].sha256 = otherDigest;
    },
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x[0].byte_count += 1;
    },
    (x: ReturnType<typeof fixture>["v"]["verification_receipt"]["objects"]) => {
      x[0].content_type = "video/mp4";
    },
  ];
  for (const edit of edits) {
    const { original, v } = fixture(3);
    assert(v.verification_receipt.objects.length > 1);
    edit(v.verification_receipt.objects);
    await rechain(v);
    await assertRejects(() => transfer(original, v));
  }
  const { original, v } = fixture();
  v.verification_receipt.objects = [];
  v.transfer_receipt.verification_receipt = structuredClone(
    v.verification_receipt,
  );
  await assertRejects(() =>
    mediaHandoffProofDigest(
      "verification_receipt",
      canon(v.verification_receipt),
    )
  );
  await assertRejects(() =>
    mediaHandoffProofDigest("transfer_receipt", canon(v.transfer_receipt))
  );
  await assertRejects(() => transfer(original, v));
});

Deno.test("media handoff: original token and original verification must match across documents", async () => {
  const { original, v } = fixture();
  const other = structuredClone(v);
  other.claim.claim_token = otherID;
  await rechain(other);
  await assertRejects(() =>
    validateMediaVerificationReceipt(
      original,
      v.claim,
      other.verification_receipt,
    )
  );
  await assertRejects(() =>
    validateMediaTransferReceipt(
      original,
      v.claim,
      v.verification_receipt,
      other.transfer_receipt,
    )
  );
  for (
    const edit of [
      (b: typeof v) => {
        b.verification_receipt.claim_digest = otherDigest;
      },
      (b: typeof v) => {
        b.transfer_receipt.verification_receipt_digest = otherDigest;
      },
      (b: typeof v) => {
        b.transfer_receipt.admission_receipt_digest = otherDigest;
      },
      (b: typeof v) => {
        b.transfer_receipt.protocol_artifact_digest = otherDigest;
      },
    ]
  ) {
    const b = structuredClone(v);
    edit(b);
    await assertRejects(() => transfer(original, b));
  }
});

Deno.test("media handoff: coherent synthetic alternate token/time passes consistency but proves no issuance", async () => {
  const { original, v } = fixture();
  v.claim.claim_token = otherID;
  v.claim.issued_at_ms += 1;
  await rechain(v);
  const result = await transfer(original, v);
  assertEquals(result.authority, "none");
  assertNotEquals(result.digest, vectors.valid[0].transfer_receipt_digest);
  assertEquals(
    JSON.parse(result.canonical).verification_receipt.claim.claim_token,
    otherID,
  );
  // No DB/clock/provider dependency exists: provenance must be enforced by the
  // future locked owner, not inferred from this successful pure validation.
});

Deno.test("media handoff: strict original cutoffs and chronology reject equality/inversion", async () => {
  for (
    const edit of [
      (v: ReturnType<typeof fixture>["v"], authorized: number) => {
        v.claim.issued_at_ms = authorized - 1;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.claim.issued_at_ms =
          v.claim.binding.phase_window.cutoffs.verification_claim;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.verification_receipt.authorized_at_ms = v.claim.issued_at_ms - 1;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.verification_receipt.authorized_at_ms =
          v.claim.binding.phase_window.cutoffs.verification_settlement;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.transfer_receipt.authorized_at_ms =
          v.verification_receipt.authorized_at_ms - 1;
      },
      (v: ReturnType<typeof fixture>["v"]) => {
        v.transfer_receipt.authorized_at_ms =
          v.claim.binding.phase_window.cutoffs.transfer;
      },
    ]
  ) {
    const { original, v } = fixture();
    edit(v, JSON.parse(original.manifest).authorized_at_ms);
    await rechain(v);
    await assertRejects(() => transfer(original, v));
  }
  const { original, v } = fixture();
  v.claim.issued_at_ms = JSON.parse(original.manifest).authorized_at_ms;
  v.verification_receipt.authorized_at_ms = v.claim.issued_at_ms;
  v.transfer_receipt.authorized_at_ms = v.claim.issued_at_ms;
  await rechain(v);
  assertEquals((await transfer(original, v)).authority, "none");
});

Deno.test("media handoff: closed shapes, bounded canonical spelling and non-JSON objects reject", async () => {
  const { original, v } = fixture();
  for (
    const value of [
      null,
      [],
      { ...v.claim, extra: true },
      { ...v.claim, version: 1 },
      { ...v.claim, issued_at_ms: Number.MAX_SAFE_INTEGER + 1 },
      { ...v.claim, issued_at_ms: -0 },
      { ...v.claim, claim_token: "F".repeat(36) },
      { ...v.claim, claim_token: "x".repeat(32769) },
      Object.assign(Object.create(null), v.claim),
    ]
  ) await assertRejects(() => validateMediaVerificationClaim(original, value));
  let getterCalls = 0;
  const access = { ...v.claim };
  Object.defineProperty(access, "claim_token", {
    get() {
      getterCalls++;
      return otherID;
    },
    enumerable: true,
  });
  await assertRejects(() => validateMediaVerificationClaim(original, access));
  assertEquals(getterCalls, 0);
  for (
    const [kind, value] of [
      ["claim", v.claim],
      ["verification_receipt", v.verification_receipt],
      ["transfer_receipt", v.transfer_receipt],
    ] as const
  ) {
    await assertRejects(() =>
      mediaHandoffProofDigest(kind, canon(value) + "\n")
    );
    await assertRejects(() =>
      mediaHandoffProofDigest(
        kind,
        " ".repeat(MEDIA_HANDOFF_PROOF_LIMITS[kind] + 1),
      )
    );
    await assertRejects(() =>
      mediaHandoffProofDigest(kind, canon({ ...value, extra: true }))
    );
  }
  await assertRejects(() =>
    mediaHandoffProofDigest(
      "constructor" as MediaHandoffProofKind,
      canon(v.claim),
    )
  );
});

Deno.test("media handoff: snapshots every caller document and original component before yielding", async () => {
  const { original, v } = fixture();
  const expected = canon(v.transfer_receipt);
  const pending = transfer(original, v);
  original.input = "{}";
  original.manifest = "{}";
  v.claim.claim_token = otherID;
  v.verification_receipt.objects[0].sha256 = otherDigest;
  v.transfer_receipt.authorized_at_ms = 0;
  assertEquals((await pending).canonical, expected);
});
