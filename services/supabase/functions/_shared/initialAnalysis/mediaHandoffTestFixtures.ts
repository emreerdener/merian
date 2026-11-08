/** Synthetic transport fixtures only: tuple bytes are deterministic buffers,
 * not media structural qualification or installed artifact evidence. */
import { initialCanonicalText as canon } from "./canonical.ts";
import {
  type AdmittedProofText,
  validateAdmittedProof,
} from "./admittedProof.ts";
import { initialMediaHash } from "./mediaBinding.ts";
import { mediaHandoffProofDigest } from "./mediaHandoffProof.ts";
import admitted from "./fixtures/admitted-proof-v1.json" with { type: "json" };
import proofs from "./fixtures/media-handoff-proof-v1.json" with {
  type: "json",
};
import catalog from "./fixtures/handoff-catalog-v1.json" with { type: "json" };
const domains = {
  candidate: "preparation-candidate.v2",
  input: "input.v1",
  configuration: "configuration.v1",
  funding: "funding.v1",
  outcome: "preparation-execution.outcome.v2",
  installation: "handoff.installation.v1",
  protocol: "handoff.protocol_artifact.v1",
  destination: "handoff.destination_backend.v1",
  mapping: "handoff.mapping.v2",
  media_binding: "handoff.media_binding.v2",
  accounting: "handoff.accounting.v1",
};
async function hash(domain: string, text: string) {
  return [
    ...new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(
          "merian.initial-analysis." + domain + "\n" + text,
        ),
      ),
    ),
  ].map((x) => x.toString(16).padStart(2, "0")).join("");
}
/** Test-only recommit allows semantic tampering to get past digest checks. */
async function recommit(b: AdmittedProofText) {
  const m = JSON.parse(b.manifest);
  for (const [key, domain] of Object.entries(domains)) {
    const k = key as keyof typeof domains;
    (k === "mapping" || k === "media_binding" ? m.metadata : m.proof)[k] = {
      digest: await hash(domain, b[k]),
      byte_count: new TextEncoder().encode(b[k]).length,
    };
  }
  m.metadata_digest = await hash(
    "handoff.admitted-metadata.v1",
    canon(m.metadata),
  );
  m.proof_digest = await hash("handoff.admitted-proof.v1", canon(m.proof));
  b.manifest = canon(m);
}
/** Propagate source/configuration edits for positive boundaries and coupled-negative controls. */
async function rebind(b: AdmittedProofText) {
  const c = JSON.parse(b.candidate),
    cfg = JSON.parse(b.configuration),
    a = cfg.assignment,
    o = JSON.parse(b.outcome),
    input = JSON.parse(b.input),
    m = JSON.parse(b.manifest),
    mapping = JSON.parse(b.mapping),
    binding = JSON.parse(b.media_binding);
  for (const member of a.preparation.source_mapping) {
    member.source = structuredClone(c.source_plan.sources[member.ordinal]);
  }
  a.candidate_digest = await hash("preparation-candidate.v2", b.candidate);
  a.source_plan_digest = await hash(
    "media.source_plan.v1",
    canon(c.source_plan),
  );
  b.configuration = canon(cfg);
  m.assignment_digest = await hash("assignment.v2", canon(a));
  for (
    const x of [
      o,
      o.grant,
      o.source_verification,
      o.output_manifest,
      o.resolved_manifest,
      mapping,
      binding,
    ]
  ) x.assignment_digest = m.assignment_digest;
  const sd = await hash(
    "preparation-execution.source_verification.v1",
    canon(o.source_verification),
  );
  o.grant.source_digest = sd;
  o.output_manifest.source_digest = sd;
  o.resolved_manifest.request_digest = await hash(
    "preparation-execution.output_manifest.v1",
    canon(o.output_manifest),
  );
  b.outcome = canon(o);
  const od = await hash("preparation-execution.outcome.v2", b.outcome);
  mapping.outcome_digest = od;
  binding.outcome_digest = od;
  b.mapping = canon(mapping);
  binding.mapping_digest = await hash("handoff.mapping.v2", b.mapping);
  input.ordered_descriptions = c.source_plan.ordered_descriptions;
  input.owner_timeline = c.source_plan.owner_timeline;
  input.admission = c.source_plan.admission;
  b.input = canon(input);
  binding.submission_digest = await hash("input.v1", b.input);
  b.media_binding = canon(binding);
  m.descriptions_digest = await hash(
    "descriptions.v1",
    canon(input.ordered_descriptions),
  );
  m.assets_digest = a.asset_manifest_digest;
  b.manifest = canon(m);
  await recommit(b);
}
async function tupleBytes(value: unknown): Promise<void> {
  if (!value || typeof value !== "object") return;
  const row = value as Record<string, unknown>;
  if (
    typeof row.content_type === "string" &&
    typeof row.byte_count === "number" && typeof row.sha256 === "string"
  ) {
    row.sha256 = await initialMediaHash(new Uint8Array(row.byte_count));
  }
  if (
    typeof row.source_byte_count === "number" &&
    typeof row.source_sha256 === "string"
  ) {
    row.source_sha256 = await initialMediaHash(
      new Uint8Array(row.source_byte_count),
    );
  }
  for (const member of Object.values(row)) await tupleBytes(member);
}
export async function handoffExecutionFixture(index = 0, stage = 0) {
  const proof = structuredClone(proofs.valid[index]);
  const components = structuredClone(
    admitted.valid[proof.admitted_vector_index].components,
  );
  for (const key of ["candidate", "input", "outcome", "mapping"] as const) {
    const value = JSON.parse(components[key]);
    await tupleBytes(value);
    components[key] = canon(value);
  }
  await rebind(components);
  const original = await validateAdmittedProof(components);
  const binding = JSON.parse(components.media_binding),
    mapping = JSON.parse(components.mapping);
  proof.claim.binding = binding;
  proof.claim.admission_receipt_digest = original.receiptDigest;
  proof.claim_digest = await mediaHandoffProofDigest(
    "claim",
    canon(proof.claim),
  );
  proof.verification_receipt.claim = proof.claim;
  proof.verification_receipt.claim_digest = proof.claim_digest;
  proof.verification_receipt.objects = mapping.objects.map((
    o: { object_id: string; bytes: object },
  ) => ({
    object_id: o.object_id,
    backend_generation: mapping.destination_backend_generation,
    ...o.bytes,
  }));
  proof.verification_receipt_digest = await mediaHandoffProofDigest(
    "verification_receipt",
    canon(proof.verification_receipt),
  );
  proof.transfer_receipt.admission_receipt_digest = original.receiptDigest;
  proof.transfer_receipt.verification_receipt = proof.verification_receipt;
  proof.transfer_receipt.verification_receipt_digest =
    proof.verification_receipt_digest;
  proof.transfer_receipt_digest = await mediaHandoffProofDigest(
    "transfer_receipt",
    canon(proof.transfer_receipt),
  );
  const scope = {
    owner_id: binding.owner_id as string,
    scan_id: binding.scan_id as string,
  };
  const identity = {
    ...scope,
    admission_receipt_digest: original.receiptDigest,
  };
  const start: number = JSON.parse(components.manifest).authorized_at_ms;
  const handoff =
    JSON.parse(components.configuration).assignment.handoff.profile;
  const allObjects = proof.verification_receipt.objects;
  let settled = stage >= 2 ? allObjects : allObjects.slice(0, 0);
  let observed = Math.max(
    start + 3,
    stage >= 4 ? proof.claim.issued_at_ms : 0,
    stage >= 5 ? proof.verification_receipt.authorized_at_ms : 0,
    stage >= 6 ? proof.transfer_receipt.authorized_at_ms : 0,
  ) + 1;
  function state() {
    const progress = stage >= 1
      ? {
        ...identity,
        copy_adapter_digest: handoff.copy_adapter_digest,
        started_at_ms: start,
        completed_objects: canon(settled),
        last_object_at_ms: settled.length ? start + 1 : null,
        completed_at_ms: stage >= 3 ? start + 2 : null,
      }
      : null;
    const claim = stage >= 4
      ? {
        ...scope,
        claim: canon(proof.claim),
        claim_digest: proof.claim_digest,
      }
      : null;
    const verification = stage >= 5
      ? {
        ...scope,
        receipt: canon(proof.verification_receipt),
        receipt_digest: proof.verification_receipt_digest,
      }
      : null;
    const transfer = stage >= 6
      ? {
        ...scope,
        receipt: canon(proof.transfer_receipt),
        receipt_digest: proof.transfer_receipt_digest,
      }
      : null;
    const phase = stage >= 5
      ? "transfer"
      : stage >= 3
      ? "verification"
      : "copy";
    const cutoff = stage >= 5
      ? "transfer"
      : stage >= 4
      ? "verification_settlement"
      : stage >= 3
      ? "verification_claim"
      : "copy";
    return {
      response: {
        version: 2,
        outcome: stage >= 6 ? "transferred" : "admitted",
        authority: "none",
        scan_id: scope.scan_id,
        admission_receipt_digest: original.receiptDigest,
        binding,
        ...(stage >= 6
          ? { transfer_receipt_digest: proof.transfer_receipt_digest }
          : {
            phase: observed >= binding.phase_window.cutoffs[cutoff]
              ? "expired"
              : phase,
          }),
      },
      admission: {
        ...scope,
        admission_receipt_id: binding.admission_receipt_id,
        receipt_digest: original.receiptDigest,
        ...components,
      },
      progress,
      claim,
      verification,
      transfer,
      observed_at_ms: observed,
    };
  }
  function io() {
    const s = state();
    return {
      admission: s.admission,
      progress: s.progress,
      claim: s.claim,
      observed_at_ms: observed,
      source_backend: {
        ...catalog.source_backend,
        configuration_digest: catalog.source_backend_digest,
      },
      destination_backend: JSON.parse(components.destination),
    };
  }
  function advance(
    next: number,
    field: "progress" | "claim" | "verification" | "transfer",
    object?: string,
  ) {
    if (object) {
      settled = [
        ...settled,
        allObjects.find((o) => o.object_id === object)!,
      ].sort((a, b) => a.object_id.localeCompare(b.object_id));
    }
    stage = next;
    if (stage >= 4) observed = Math.max(observed, proof.claim.issued_at_ms);
    if (stage >= 5) {
      observed = Math.max(
        observed,
        proof.verification_receipt.authorized_at_ms,
      );
    }
    if (stage >= 6) {
      observed = Math.max(observed, proof.transfer_receipt.authorized_at_ms);
    }
    const s = state();
    return { response: s.response, [field]: s[field] };
  }
  return {
    identity,
    components,
    mapping,
    handoff,
    binding,
    proof,
    state,
    io,
    advance,
    setObserved: (value: number) => {
      observed = value;
    },
    getObserved: () => observed,
  };
}
