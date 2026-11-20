/** Portable protocol tests. All process replies below are synthetic, never artifact qualification. */
import { ownerFixture, syntheticWav } from "./owner-fixture.ts";
import { base64, byteDigest, createOwnerRuntime } from "./owner-exchange.ts";
import {
  reconcileInitialPreparationOutput,
  runInitialPreparation,
} from "../../services/supabase/functions/_shared/initialAnalysis/preparationExecution.ts";
function assert(value: unknown): asserts value {
  if (!value) throw new Error("assertion failed");
}
const signal = () => new AbortController().signal;
function prepared() {
  const bytes = syntheticWav().slice(0, 32044), v = new DataView(bytes.buffer);
  v.setUint32(4, 32036, true);
  v.setUint32(24, 16000, true);
  v.setUint32(28, 32000, true);
  v.setUint32(40, 32000, true);
  return bytes;
}
async function reply(frame: string): Promise<string> {
  const request = JSON.parse(frame),
    source = syntheticWav(),
    output = prepared();
  assert(request.request.base64 === base64(source));
  return JSON.stringify({
    version: 1,
    kind: "prepared",
    grant_id: request.grant_id,
    source_digest: request.source_digest,
    ordinal: 0,
    answer: {
      version: 2,
      operation: "validated_wav16k",
      preserve_source_when_trimmed_too_short: false,
      input_bytes: source.length,
      input_sha256: await byteDigest(source),
      output_bytes: output.length,
      output_sha256: await byteDigest(output),
      base64: base64(output),
      complete: true,
    },
  }) + "\n";
}
Deno.test("local fixture completes and replays original output with one synthetic exchange", async () => {
  let exchanges = 0;
  const f = await ownerFixture(createOwnerRuntime(async (frame) => {
    exchanges++;
    return await reply(frame);
  }));
  f.mutateSource();
  const first = await runInitialPreparation(f.deps, f.input, signal());
  assert(first.kind === "outcome_ready");
  assert(
    first.outcome.output_manifest.entries[0].prepared?.bytes.sha256 ===
      await byteDigest(prepared()),
  );
  const replay = await runInitialPreparation(f.deps, f.input, signal());
  assert(
    replay.kind === "outcome_ready" && exchanges === 1 &&
      f.counts.runtime === 1 && f.counts.issues === 1,
  );
});
Deno.test("lost original issuance reply never reaches the pipe", async () => {
  let exchanges = 0;
  const f = await ownerFixture(createOwnerRuntime(async (frame) => {
    exchanges++;
    return await reply(frame);
  }));
  f.setLoss("issue_initial_preparation_execution");
  assert(
    (await runInitialPreparation(f.deps, f.input, signal())).kind ===
      "recovery_needed",
  );
  assert(
    (await runInitialPreparation(f.deps, f.input, signal())).kind ===
      "recovery_needed",
  );
  assert(exchanges === 0 && f.counts.runtime === 0 && f.counts.issues === 1);
});
for (
  const loss of [
    "register_initial_preparation_output",
    "settle_initial_preparation_outcome",
  ] as const
) {
  Deno.test(`known original local bytes reconcile ${loss} without another exchange`, async () => {
    let exchanges = 0;
    const f = await ownerFixture(createOwnerRuntime(async (frame) => {
      exchanges++;
      return await reply(frame);
    }));
    f.setLoss(loss);
    const first = await runInitialPreparation(f.deps, f.input, signal());
    assert(first.kind === "recovery_needed" && first.known);
    const recovered = await reconcileInitialPreparationOutput(
      f.deps,
      first.known,
      signal(),
    );
    assert(
      recovered.kind === "outcome_ready" && exchanges === 1 &&
        f.counts.runtime === 1,
    );
  });
}
for (
  const corruption of [
    "grant",
    "source",
    "ordinal",
    "count",
    "digest",
    "extra",
    "duplicate",
    "truncated",
  ]
) {
  Deno.test(`local runtime rejects ${corruption} reply and never repeats`, async () => {
    let exchanges = 0;
    const f = await ownerFixture(createOwnerRuntime(async (frame) => {
      exchanges++;
      const raw = await reply(frame), v = JSON.parse(raw);
      if (corruption === "grant") {
        v.grant_id = "00000000-0000-4000-8000-000000009999";
      }
      if (corruption === "source") v.source_digest = "0".repeat(64);
      if (corruption === "ordinal") v.ordinal = 1;
      if (corruption === "count") v.answer.output_bytes++;
      if (corruption === "digest") v.answer.output_sha256 = "0".repeat(64);
      if (corruption === "extra") v.extra = true;
      if (corruption === "duplicate") {
        return raw.replace('"version":1', '"version":1,"version":1');
      }
      if (corruption === "truncated") return raw.slice(0, -8);
      return JSON.stringify(v) + "\n";
    }));
    assert(
      (await runInitialPreparation(f.deps, f.input, signal())).kind ===
        "recovery_needed",
    );
    assert(
      (await runInitialPreparation(f.deps, f.input, signal())).kind ===
        "recovery_needed",
    );
    assert(exchanges === 1 && f.counts.issues === 1);
  });
}
for (const stage of ["validation", "transform"] as const) {
  Deno.test(`known local ${stage} rejection preserves original status recovery`, async () => {
    let exchanges = 0;
    const f = await ownerFixture(createOwnerRuntime((frame) => {
      exchanges++;
      const v = JSON.parse(frame);
      return Promise.resolve(
        JSON.stringify({
          version: 1,
          kind: "rejected",
          grant_id: v.grant_id,
          source_digest: v.source_digest,
          ordinal: 0,
          stage,
        }) + "\n",
      );
    }));
    assert(
      (await runInitialPreparation(f.deps, f.input, signal())).kind ===
        "recovery_needed",
    );
    assert(
      (await runInitialPreparation(f.deps, f.input, signal())).kind ===
        "recovery_needed",
    );
    assert(
      exchanges === 1 && f.saved().result === null && f.saved().output === null,
    );
  });
}
Deno.test("changed verified source is rejected before local pipe I/O", async () => {
  let exchanges = 0;
  const adapter = createOwnerRuntime(async (frame) => {
    exchanges++;
    return await reply(frame);
  });
  const f = await ownerFixture((input, s) =>
    adapter({ ...input, read: () => new Uint8Array(64044) }, s)
  );
  assert(
    (await runInitialPreparation(f.deps, f.input, signal())).kind ===
      "recovery_needed",
  );
  assert(exchanges === 0);
});
Deno.test("source structural rejection does not issue or transform", async () => {
  let exchanges = 0;
  const f = await ownerFixture(createOwnerRuntime(async (frame) => {
    exchanges++;
    return await reply(frame);
  }));
  f.deps.inspectSource = () => {
    throw new Error("synthetic structure rejection");
  };
  assert(
    (await runInitialPreparation(f.deps, f.input, signal())).kind !==
      "outcome_ready",
  );
  assert(f.counts.issues === 0 && f.counts.runtime === 0 && exchanges === 0);
});

for (
  const field of [
    "issued_at_ms",
    "execution_deadline_ms",
    "registration_deadline_ms",
    "outcome_deadline_ms",
  ] as const
) {
  Deno.test(`changed otherwise valid original grant ${field} cannot reach local pipe`, async () => {
    let exchanges = 0;
    const adapter = createOwnerRuntime(async (frame) => {
      exchanges++;
      return await reply(frame);
    });
    const f = await ownerFixture((input, s) =>
      adapter({
        ...input,
        grant: { ...input.grant, [field]: input.grant[field] + 1 },
      }, s)
    );
    assert(
      (await runInitialPreparation(f.deps, f.input, signal())).kind ===
        "recovery_needed",
    );
    assert(
      (await runInitialPreparation(f.deps, f.input, signal())).kind ===
        "recovery_needed",
    );
    assert(exchanges === 0 && f.counts.runtime === 1 && f.counts.issues === 1);
  });
}
