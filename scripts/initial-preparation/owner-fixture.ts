import {
  executionDigest,
  preparationContext,
  type PreparationGrant,
  type PreparationOutcome,
  type PreparationOutputReceipt,
  type PreparationResolvedManifest,
  type PreparationSourceReceipt,
} from "../../services/supabase/functions/_shared/initialAnalysis/preparationExecutionContract.ts";
import {
  type PreparationExecutionDependencies,
  type PreparationOperation,
} from "../../services/supabase/functions/_shared/initialAnalysis/preparationExecution.ts";
import vectorInput from "./owner-fixture.json" with { type: "json" };
import { inspectInitialWavStructure } from "../../services/supabase/functions/_shared/initialAnalysis/wavValidation.ts";

export function syntheticWav(): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(64044), view = new DataView(bytes.buffer);
  for (
    const [at, text] of [[0, "RIFF"], [8, "WAVEfmt "], [36, "data"]] as const
  ) bytes.set(new TextEncoder().encode(text), at);
  view.setUint32(4, 64036, true);
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, 32000, true);
  view.setUint32(28, 64000, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  view.setUint32(40, 64000, true);
  for (let i = 44; i < bytes.length; i += 2) view.setInt16(i, 8192, true);
  return bytes;
}

/** Fixed synthetic state only. No RPC, installed profile or provider transport. */
export async function ownerFixture(
  runtime: PreparationExecutionDependencies["runtime"],
) {
  const vector = structuredClone(vectorInput);
  const bytes = syntheticWav();
  const input = {
    owner: "00000000-0000-4000-8000-000000001001",
    scan: "00000000-0000-4000-8000-000000001002",
    candidate: vector.candidate,
    assignment: vector.assignment,
    profile: vector.profile,
  };
  const ctx = await preparationContext(
    input.scan,
    input.candidate,
    input.assignment,
    input.profile,
  );
  const base = 1000000, expiry = base + 300000;
  let source: PreparationSourceReceipt | null = null,
    grant: PreparationGrant | null = null,
    output: {
      request: PreparationOutputReceipt;
      resolved: PreparationResolvedManifest;
    } | null = null,
    result: PreparationOutcome | null = null;
  const calls: PreparationOperation[] = [],
    counts = { runtime: 0, reads: 0, retains: 0, issues: 0 };
  const now = () => base; // Fixed virtual fixture clock, not a production server.
  const id = {
    version: 1 as const,
    scan_id: input.scan,
    assignment_digest: ctx.assignment_digest,
  };
  let failAfter: PreparationOperation | null = null,
    terminal = false,
    mutate = false;
  const originalBytes = new Uint8Array(bytes);
  const deps: PreparationExecutionDependencies = {
    async call(op, args, _signal) {
      calls.push(op);
      if (terminal) return { version: 1, outcome: "held", reason: "expired" };
      let answer: unknown;
      if (op === "get_initial_preparation_execution_status") {
        return {
          version: 1,
          outcome: "status",
          phase: result
            ? "outcome_ready"
            : output
            ? "output_registered"
            : grant
            ? "issued"
            : source
            ? "verified"
            : "allocated",
          source,
          execution_reference: grant
            ? { grant_id: grant.grant_id, source_digest: grant.source_digest }
            : null,
          output,
          result,
          server_now_ms: now(),
          expires_at_ms: expiry,
        };
      }
      if (op === "settle_initial_preparation_sources") {
        source = JSON.parse(String(args.p_receipt));
        answer = {
          version: 1,
          outcome: "verified",
          receipt: source,
          digest: await executionDigest(
            "source_verification",
            String(args.p_receipt),
          ),
        };
      } else if (op === "issue_initial_preparation_execution") {
        if (grant) {
          return { version: 1, outcome: "held", reason: "preparation_issued" };
        }
        counts.issues++;
        const issued = now(), wall = vector.profile.spec.limits.wall_ms;
        grant = {
          ...id,
          grant_id: "00000000-0000-4000-8000-000000001003",
          source_digest: String(args.p_source_digest),
          profile_digest: ctx.assignment.preparation.profile_digest,
          artifact_digest: vector.profile.spec.artifact.sha256,
          issued_at_ms: issued,
          execution_deadline_ms: issued + 5000 + wall,
          registration_deadline_ms: issued + 10000 + wall,
          outcome_deadline_ms: issued + 45000 + wall,
        };
        answer = {
          version: 1,
          outcome: "granted",
          grant,
          server_now_ms: now(),
          expires_at_ms: expiry,
        };
      } else if (op === "register_initial_preparation_output") {
        const request = JSON.parse(
          String(args.p_manifest),
        ) as PreparationOutputReceipt;
        const resolved: PreparationResolvedManifest = {
          ...id,
          grant_id: grant!.grant_id,
          request_digest: await executionDigest(
            "output_manifest",
            String(args.p_manifest),
          ),
          entries: [{
            ordinal: 0,
            object_id: vector.output_id,
          }],
        };
        output = { request, resolved };
        answer = { version: 1, outcome: "registered", ...output };
      } else {
        result = JSON.parse(String(args.p_outcome));
        answer = {
          version: 1,
          outcome: "outcome_ready",
          result,
          digest: await executionDigest("outcome", String(args.p_outcome)),
        };
      }
      if (failAfter === op) {
        failAfter = null;
        throw new Error("synthetic lost reply");
      }
      return structuredClone(answer);
    },
    readSource() {
      counts.reads++;
      return Promise.resolve(bytes);
    },
    inspectSource(_i, copy) {
      const facts = inspectInitialWavStructure(new Uint8Array(copy));
      if (mutate) bytes.fill(255);
      return Promise.resolve({
        image: null,
        mp4: null,
        wav: {
          format: facts.format === 1 ? "pcm16" as const : "float32" as const,
          sample_rate: facts.rate,
          channels: facts.channels,
          frames: facts.frameCount,
        },
      });
    },
    runtime(value, signal) {
      counts.runtime++;
      return runtime(value, signal);
    },
    verifyExistingIdentityOutput() {
      counts.retains++;
      return Promise.resolve(new Uint8Array(originalBytes));
    },
    createFreshOutputAndReadBack(_i, _id, value) {
      counts.retains++;
      return Promise.resolve(value);
    },
  };
  // Eligibility is fixed before the real owner may issue any local grant.
  if (
    !vector.synthetic_only || vector.edge_eligible ||
    vector.resource_status !== "sampled_local_only" ||
    ctx.assignment_digest !== vector.assignment_digest ||
    bytes.length > 192000 ||
    vector.profile.spec.profile_id !== "local_validated_wav_fixture" ||
    vector.profile.spec.runtime.abi !== "local_synthetic_only" ||
    vector.assignment.preparation.source_mapping.length !== 1 ||
    vector.candidate.source_plan.sources[0].clip_index !== null
  ) throw new Error("local_fixture_ineligible");
  const request = JSON.stringify({
    version: 2,
    operation: "validated_wav16k",
    base64: btoa(String.fromCharCode(...bytes)),
    preserve_source_when_trimmed_too_short: false,
  });
  if (request.length > 262144 || Math.ceil(bytes.length / 3) * 4 > 256000) {
    throw new Error("local_fixture_envelope");
  }
  return {
    input,
    ctx,
    deps,
    counts,
    calls,
    bytes,
    setLoss(op: PreparationOperation) {
      failAfter = op;
    },
    setTerminal() {
      terminal = true;
    },
    mutateSource() {
      mutate = true;
    },
    saved() {
      return { source, grant, output, result };
    },
  };
}
