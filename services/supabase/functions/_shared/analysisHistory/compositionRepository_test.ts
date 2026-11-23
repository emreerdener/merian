import { assert, assertEquals, assertRejects } from "@std/assert";
import type { SupabaseClient } from "@supabase/supabase-js";
import { compositionSourceReservationRepository } from "./compositionSourceReservationRepository.ts";
import { compositionEvidenceRepository } from "./compositionEvidenceRepository.ts";
import { compositionSourceIdentity } from "./compositionSourceReservation.ts";
import { compositionFingerprint } from "./compositionFingerprint.ts";
import { compositionCohortItems } from "./compositionCohort.ts";
import { parseCompositionAdmission } from "./compositionAdmission.ts";
import vectors from "./fixtures/composition-request-v5.json" with {
  type: "json",
};
const owner = "00000000-0000-4000-8000-000000009000";
const bytes = (v: unknown) => new TextEncoder().encode(JSON.stringify(v));
const signal = () => new AbortController().signal;
async function candidate(value: unknown = vectors[0].input) {
  const input = parseCompositionAdmission(value);
  return {
    schema_version: 3,
    input,
    fingerprint_version: 1,
    fingerprint: await compositionFingerprint(input),
  };
}
type Call = {
  routine: string;
  args: Record<string, unknown>;
  signal: AbortSignal;
};
function fixture(
  reply: (call: Call) => Promise<{ data: unknown; error: unknown }>,
) {
  const calls: Call[] = [];
  const client = {
    rpc(routine: string, args: Record<string, unknown>) {
      return {
        abortSignal(signal: AbortSignal) {
          const call = { routine, args, signal };
          calls.push(call);
          return reply(call);
        },
      };
    },
  } as unknown as SupabaseClient;
  return {
    source: compositionSourceReservationRepository(client),
    evidence: compositionEvidenceRepository(client),
    calls,
  };
}
async function allocation(value: unknown = vectors[0].input) {
  const original = await candidate(value),
    identity = await compositionSourceIdentity(original);
  const items = compositionCohortItems(original.input);
  const request = { ...identity, items };
  const receipt = {
    ...identity,
    owner_id: owner,
    state: "allocated",
    expires_at: "2026-01-01T00:00:00.000Z",
    items: items.map((item, i) => ({
      ...item,
      object_id: `00000000-0000-4000-8000-${
        String(8000 + i).padStart(12, "0")
      }`,
      ready_at: null as string | null,
    })),
  };
  return { original, request, receipt };
}
Deno.test("composition source adapter binds reader14 and whole identity across all media shapes", async () => {
  for (const row of vectors.filter((r) => r.valid)) {
    const original = await candidate(row.input),
      identity = await compositionSourceIdentity(original);
    for (const method of ["reserve", "recover"] as const) {
      for (
        const reply of [{ ...identity, owner_id: owner, state: "reserved" }, {
          ...identity,
          owner_id: owner,
          state: "unavailable",
        }, {
          ...identity,
          owner_id: owner,
          state: "held",
          reason: "terminal_unproven",
        }]
      ) {
        const f = fixture(() => Promise.resolve({ data: reply, error: null }));
        assertEquals<unknown>(
          await f.source[method](owner, original, signal()),
          reply,
        );
        assertEquals(f.calls.length, 1);
        assertEquals(
          f.calls[0].routine,
          method === "reserve"
            ? "reserve_owned_observation_composition_source"
            : "get_owned_observation_composition_source",
        );
        assertEquals(f.calls[0].args, {
          p_owner: owner,
          p_request: method === "reserve" ? original : identity,
          p_reader: 14,
        });
      }
    }
  }
});
Deno.test("composition allocation and completion retain every ordered artifact and expired replay identity", async () => {
  for (const row of vectors.filter((r) => r.valid)) {
    const { original, request, receipt } = await allocation(row.input);
    const f = fixture(() => Promise.resolve({ data: receipt, error: null }));
    assertEquals<unknown>(
      await f.evidence.reserve(owner, original, signal()),
      receipt,
    );
    assertEquals(f.calls[0].args, {
      p_owner: owner,
      p_request: request,
      p_reader: 14,
    });
    assertEquals(
      f.calls[0].routine,
      "reserve_owned_observation_composition_evidence",
    );
    const ready = {
      ...receipt,
      state: "ready",
      items: receipt.items.map((item) => ({
        ...item,
        ready_at: "2025-12-31T23:59:00.000Z",
      })),
    };
    for (const item of receipt.items) {
      const f = fixture(() => Promise.resolve({ data: ready, error: null }));
      assertEquals<unknown>(
        await f.evidence.complete(
          owner,
          original,
          bytes(receipt),
          item.media_id,
          signal(),
        ),
        ready,
      );
      assertEquals(
        f.calls[0].routine,
        "complete_owned_observation_composition_evidence",
      );
      assertEquals(f.calls[0].args, {
        p_owner: owner,
        p_request: request,
        p_media: item.media_id,
        p_object: item.object_id,
        p_reader: 14,
      });
    }
  }
});
Deno.test("composition adapters refuse invalid input before RPC and never downgrade malformed replies", async () => {
  const { original, receipt } = await allocation();
  const source = {
    ...await compositionSourceIdentity(original),
    owner_id: owner,
    state: "reserved",
  };
  for (const adapter of ["source", "evidence"] as const) {
    const f = fixture(() => Promise.resolve({ data: null, error: null }));
    await assertRejects(() =>
      f[adapter].reserve(owner, { ...original, schema_version: 2 }, signal())
    );
    assertEquals(f.calls.length, 0);
    const good = adapter === "source" ? source : receipt;
    for (
      const bad of [
        { ...good, owner_id: original.input.analysis_id },
        { ...good, fingerprint: "0".repeat(64) },
        { ...good, dispatch: true },
        "x".repeat(16385),
      ]
    ) {
      const f = fixture(() => Promise.resolve({ data: bad, error: null }));
      await assertRejects(() => f[adapter].reserve(owner, original, signal()));
      assertEquals(f.calls.length, 1);
    }
  }
  for (
    const mutate of [
      (r: typeof receipt) => {
        r.items[0].object_id = "00000000-0000-4000-8000-000000008999";
      },
      (r: typeof receipt) => {
        r.expires_at = "2027-01-01T00:00:00.000Z";
      },
      (r: typeof receipt) => {
        r.items[0].ready_at = null;
        r.state = "allocated";
      },
    ]
  ) {
    const ready = structuredClone(receipt);
    ready.state = "ready";
    ready.items[0].ready_at = "2025-12-31T23:59:00.000Z";
    const changed = structuredClone(ready);
    mutate(changed);
    const f = fixture(() => Promise.resolve({ data: changed, error: null }));
    await assertRejects(() =>
      f.evidence.complete(
        owner,
        original,
        bytes(ready),
        receipt.items[0].media_id,
        signal(),
      )
    );
    assertEquals(f.calls.length, 1);
  }
});
Deno.test("composition adapters snapshot candidates before hashing and never retry failures", async () => {
  for (const adapter of ["source", "evidence"] as const) {
    const { original, receipt } = await allocation();
    const before = structuredClone(original);
    const reply = adapter === "source"
      ? {
        ...await compositionSourceIdentity(original),
        owner_id: owner,
        state: "reserved",
      }
      : receipt;
    const f = fixture((call) => {
      assertEquals(
        (call.args.p_request as Record<string, unknown>).fingerprint,
        before.fingerprint,
      );
      return Promise.resolve({ data: reply, error: null });
    });
    const mutable = {
      ...original,
      input: {
        ...original.input,
        evidence_manifest: {
          ...original.input.evidence_manifest,
          items: [...original.input.evidence_manifest.items],
        },
      },
    };
    const pending = f[adapter].reserve(owner, mutable, signal());
    mutable.input.request_digest = "b".repeat(64);
    mutable.input.evidence_manifest.items.reverse();
    await pending;
    for (
      const message of [
        "analysis_history_operation_conflict",
        "private failure",
      ]
    ) {
      const f = fixture(() =>
        Promise.resolve({ data: null, error: { message } })
      );
      const error = await assertRejects(() =>
        f[adapter].reserve(owner, before, signal())
      );
      assert(error instanceof Error);
      assertEquals(
        error.message,
        message === "private failure"
          ? "analysis_history_unavailable"
          : message,
      );
      assertEquals(f.calls.length, 1);
    }
  }
});
Deno.test("composition adapters cancel stalled transport and reject late answers without retry", async () => {
  const { original } = await allocation();
  for (const adapter of ["source", "evidence"] as const) {
    const controller = new AbortController();
    let entered!: () => void,
      finish!: (v: { data: unknown; error: null }) => void;
    const started = new Promise<void>((resolve) => entered = resolve);
    const f = fixture(() => {
      entered();
      return new Promise((resolve) => finish = resolve);
    });
    const pending = f[adapter].reserve(owner, original, controller.signal);
    await started;
    controller.abort();
    await assertRejects(() => pending);
    finish({ data: null, error: null });
    await Promise.resolve();
    assertEquals(f.calls.length, 1);
    assert(f.calls[0].signal.aborted);
    await assertRejects(() =>
      f[adapter].reserve(owner, original, controller.signal)
    );
    assertEquals(f.calls.length, 1);
  }
});
