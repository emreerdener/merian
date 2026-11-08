import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import admitted from "./fixtures/admitted-proof-v1.json" with { type: "json" };
import proofs from "./fixtures/media-handoff-proof-v1.json" with {
  type: "json",
};
import catalog from "./fixtures/handoff-catalog-v1.json" with { type: "json" };
import { initialCanonicalText } from "./canonical.ts";
import { decodeHandoffIO, decodeHandoffState } from "./mediaHandoffRows.ts";

function fixture(stage = 4, index = 0) {
  const proof = proofs.valid[index],
    original = admitted.valid[proof.admitted_vector_index];
  const components = structuredClone(original.components),
    binding = JSON.parse(components.media_binding),
    mapping = JSON.parse(components.mapping),
    handoff = JSON.parse(components.configuration).assignment.handoff.profile;
  const identity = {
    owner_id: binding.owner_id as string,
    scan_id: binding.scan_id as string,
    admission_receipt_digest: original.receipt_digest,
  };
  const scope = { owner_id: identity.owner_id, scan_id: identity.scan_id };
  const start = JSON.parse(components.manifest).authorized_at_ms;
  const progress = stage > 0
    ? {
      ...scope,
      admission_receipt_digest: identity.admission_receipt_digest,
      copy_adapter_digest: handoff.copy_adapter_digest as string,
      started_at_ms: start as number,
      completed_objects: initialCanonicalText(
        stage > 1
          ? mapping.objects.map((o: { object_id: string; bytes: object }) => ({
            object_id: o.object_id,
            backend_generation: mapping.destination_backend_generation,
            ...o.bytes,
          }))
          : [],
      ),
      last_object_at_ms: stage > 1 ? start + 1 : null,
      completed_at_ms: stage > 2 ? start + 2 : null,
    }
    : null;
  const claim = stage > 3
    ? {
      ...scope,
      claim: initialCanonicalText(proof.claim),
      claim_digest: proof.claim_digest,
    }
    : null;
  const verification = stage > 4
    ? {
      ...scope,
      receipt: initialCanonicalText(proof.verification_receipt),
      receipt_digest: proof.verification_receipt_digest,
    }
    : null;
  const transfer = stage > 5
    ? {
      ...scope,
      receipt: initialCanonicalText(proof.transfer_receipt),
      receipt_digest: proof.transfer_receipt_digest,
    }
    : null;
  const observed_at_ms = Math.max(
    start + 3,
    stage > 3 ? proof.claim.issued_at_ms : 0,
    stage > 4 ? proof.verification_receipt.authorized_at_ms : 0,
    stage > 5 ? proof.transfer_receipt.authorized_at_ms : 0,
  ) + 1;
  const response = {
    version: 2,
    outcome: stage > 5 ? "transferred" : "admitted",
    authority: "none",
    scan_id: identity.scan_id,
    admission_receipt_digest: identity.admission_receipt_digest,
    binding,
    ...(stage > 5
      ? { transfer_receipt_digest: proof.transfer_receipt_digest }
      : {
        phase: stage > 4 ? "transfer" : stage > 2 ? "verification" : "copy",
      }),
  };
  const state = {
    response,
    admission: {
      ...scope,
      admission_receipt_id: binding.admission_receipt_id as string,
      receipt_digest: identity.admission_receipt_digest,
      ...components,
    },
    progress,
    claim,
    verification,
    transfer,
    observed_at_ms,
  };
  const io = {
    admission: state.admission,
    progress,
    claim,
    observed_at_ms,
    source_backend: {
      ...catalog.source_backend,
      configuration_digest: catalog.source_backend_digest,
    },
    destination_backend: JSON.parse(components.destination),
  };
  return { identity, state, io, proof };
}
for (let stage = 0; stage <= 6; stage++) {
  Deno.test(
    "handoff private rows preserve original stage " + stage,
    async () => {
      const f = fixture(stage),
        rows = await decodeHandoffState(f.state, f.identity);
      assertEquals(
        rows.original,
        f.state.admission && admitted.valid[0].components,
      );
      assertEquals(
        rows.progress?.completed_at_ms ?? null,
        f.state.progress?.completed_at_ms ?? null,
      );
      assertEquals(
        rows.claim?.digest ?? null,
        f.state.claim?.claim_digest ?? null,
      );
      assertEquals(
        rows.transfer?.digest ?? null,
        f.state.transfer?.receipt_digest ?? null,
      );
      assertThrows(() => {
        rows.binding.scan_id = "changed";
      });
    },
  );
}
for (const stage of [0, 1, 3, 4, 5]) {
  Deno.test(
    "handoff expired original state remains data at stage " + stage,
    async () => {
      const f = fixture(stage);
      f.state.observed_at_ms =
        JSON.parse(f.state.admission.media_binding).phase_window
          .original_expires_at_ms + 1;
      Object.assign(f.state.response, { phase: "expired" });
      await decodeHandoffState(f.state, f.identity);
    },
  );
}
for (const [phase, stage] of [["copy", 1], ["verification", 4]] as const) {
  Deno.test(
    "handoff fresh loader decodes pinned " + phase + " facts",
    async () => {
      const f = fixture(stage),
        io = await decodeHandoffIO(
          f.io,
          f.identity,
          phase,
          phase === "verification" ? f.proof.claim.claim_token : null,
        );
      assertEquals(
        io.sourceBackend.generation,
        io.rows.handoff.source_backend_generation,
      );
      assertEquals(
        io.destinationBackend.generation,
        io.rows.mapping.destination_backend_generation,
      );
    },
  );
}
for (
  const kind of [
    "digest",
    "owner",
    "claim_digest",
    "claim_chain",
    "progress_tuple",
    "progress_time",
    "completion",
    "response",
    "observed",
    "missing_field",
    "extra_field",
  ]
) {
  Deno.test("handoff private rows reject " + kind, async () => {
    const f = fixture();
    switch (kind) {
      case "digest":
        f.state.admission.receipt_digest = "f".repeat(64);
        break;
      case "owner":
        f.state.admission.owner_id = "00000000-0000-4000-8000-000000000099";
        break;
      case "claim_digest":
        f.state.claim!.claim_digest = "f".repeat(64);
        break;
      case "claim_chain":
        f.state.progress!.completed_at_ms = null;
        break;
      case "progress_tuple": {
        const objects = JSON.parse(f.state.progress!.completed_objects);
        objects[0].sha256 = "f".repeat(64);
        f.state.progress!.completed_objects = initialCanonicalText(objects);
        break;
      }
      case "progress_time":
        f.state.progress!.started_at_ms = 0;
        break;
      case "completion":
        f.state.progress!.completed_objects = "[]";
        break;
      case "response":
        Object.assign(f.state.response, { phase: "copy" });
        break;
      case "observed":
        f.state.observed_at_ms = NaN;
        break;
      case "missing_field":
        Reflect.deleteProperty(f.state, "transfer");
        break;
      case "extra_field":
        Object.assign(f.state, { authority: "fresh" });
        break;
    }
    await assertRejects(() => decodeHandoffState(f.state, f.identity));
  });
}
Deno.test("handoff decoder snapshots all private rows before first await", async () => {
  const f = fixture(),
    pending = decodeHandoffState(f.state, f.identity),
    digest = f.state.claim!.claim_digest;
  f.state.claim!.claim_digest = "f".repeat(64);
  f.state.progress!.completed_objects = "[]";
  f.state.response.binding.scan_id = "changed";
  const rows = await pending;
  assertEquals(rows.claim?.digest, digest);
  assertEquals(rows.identity.scan_id, f.identity.scan_id);
});
for (
  const kind of ["source", "destination", "claim", "late", "regressed", "stage"]
) {
  Deno.test("handoff fresh facts reject " + kind, async () => {
    const f = fixture();
    let token = f.proof.claim.claim_token;
    if (kind === "source") {
      f.io.source_backend.private_bucket = "changed-bucket";
    }
    if (kind === "destination") {
      f.io.destination_backend.private_bucket = "changed-bucket";
    }
    if (kind === "claim") token = "00000000-0000-4000-8000-000000000099";
    if (kind === "late") {
      f.io.observed_at_ms =
        f.state.response.binding.phase_window.cutoffs.verification;
    }
    if (kind === "regressed") f.io.observed_at_ms = 0;
    if (kind === "stage") f.io.progress!.completed_at_ms = null;
    await assertRejects(() =>
      decodeHandoffIO(f.io, f.identity, "verification", token)
    );
  });
}
Deno.test("handoff fresh copy rejects fully settled progress and any claim", async () => {
  for (const stage of [0, 2, 3, 4]) {
    const f = fixture(stage);
    await assertRejects(() => decodeHandoffIO(f.io, f.identity, "copy", null));
  }
});
Deno.test("handoff bounded canonical components reject oversized text", async () => {
  const f = fixture();
  f.state.admission.manifest = "x".repeat(8193);
  await assertRejects(() => decodeHandoffState(f.state, f.identity));
});
for (let stage = 0; stage <= 6; stage++) {
  Deno.test(
    "handoff state rejects server observation before durable stage " + stage,
    async () => {
      const f = fixture(stage);
      const s = f.state;
      const latest = Math.max(
        JSON.parse(s.admission.manifest).authorized_at_ms,
        s.progress?.started_at_ms ?? 0,
        s.progress?.last_object_at_ms ?? 0,
        s.progress?.completed_at_ms ?? 0,
        stage >= 4 ? f.proof.claim.issued_at_ms : 0,
        stage >= 5 ? f.proof.verification_receipt.authorized_at_ms : 0,
        stage >= 6 ? f.proof.transfer_receipt.authorized_at_ms : 0,
      );
      s.observed_at_ms = latest - 1;
      await assertRejects(() => decodeHandoffState(s, f.identity));
    },
  );
}
