import { assertEquals } from "@std/assert";
import { attempt, fixture, owner } from "./fixtures.ts";
import { initialPhotoTransfer } from "./handler.ts";
import { snapshotCpmWriteClosureInput } from "../_shared/initialAnalysis/cpmPhotoWriteClosure.ts";

Deno.test("role progress returns only the exact live member, denies uncertain/retired writes, never issues", async (t) => {
  for (
    const fault of [
      "source",
      "ai",
      "display",
      "owner",
      "missing",
      "open",
      "other_attempt",
      "no_live_receipt",
      "marker",
      "retired_after_receipt",
      "other_policy",
      "other_object",
      "malformed",
    ]
  ) {
    await t.step(fault, async () => {
      const index = Math.max(0, ["source", "ai", "display"].indexOf(fault));
      const f = await fixture(index);
      const obs = f.fresh.observation, calls: string[] = [];
      const body = {
        ...f.status,
        version: 2,
        action: "role_progress",
        attempt_id: fault === "other_attempt" ? owner : attempt,
        ...(fault === "malformed" ? { owner } : {}),
      };
      const observed = new Date(obs.binding.issued_at_ms + 1).toISOString()
        .replace("Z", "000Z");
      f.deps.progress = {
        readStatus(identity) {
          calls.push("status");
          if (identity.owner !== owner) throw new Error("owner unavailable");
          return Promise.resolve({
            version: 1,
            authority: "none",
            scan_id: identity.scan,
            assignment_digest: identity.assignment_digest,
            object_id: identity.object,
            attempt: fault === "missing" ? null : {
              attempt_id: attempt,
              state: "may_have_issued",
              created_at_ms: f.fresh.created_at_ms,
              capability_expires_at_ms: f.fresh.capability_expires_at_ms,
              write_closed: fault !== "open",
            },
          });
        },
        readReceipt(id, outcome) {
          calls.push("receipt");
          assertEquals([id, outcome], [attempt, "live_object"]);
          return Promise.resolve(
            fault === "no_live_receipt" ? null : {
              attempt_id: attempt,
              outcome: fault === "marker" ? "retired_marker" : outcome,
              observed_at: observed,
              claim_digest: null,
              policy_digest: fault === "other_policy"
                ? "c".repeat(64)
                : f.entry.policy_digest,
            },
          );
        },
        load(id, outcome) {
          calls.push("current");
          if (fault === "retired_after_receipt") {
            throw new Error("live observation unavailable");
          }
          return Promise.resolve(
            snapshotCpmWriteClosureInput(
              {
                ...obs,
                binding: {
                  ...obs.binding,
                  object_id: fault === "other_object"
                    ? owner
                    : obs.binding.object_id,
                },
              },
              id,
              outcome,
            ),
          );
        },
      };
      const res = await initialPhotoTransfer(
        new Request("https://synthetic.invalid/transfer"),
        body,
        fault === "owner" ? attempt : owner,
        () => f.deps,
      );
      if (["source", "ai", "display"].includes(fault)) {
        assertEquals(res.status, 200);
        assertEquals(await res.json(), {
          version: 2,
          outcome: "live_role_observed",
          authority: "none",
          owner_id: owner,
          scan_id: f.request.scan_id,
          assignment_digest: f.request.assignment_digest,
          object_id: f.request.object_id,
          attempt_id: attempt,
          role: obs.target.role,
          byte_count: obs.target.byte_count,
          content_type: obs.target.content_type,
          sha256: obs.target.sha256,
          backend_generation: obs.binding.backend_generation,
          backend_configuration_digest: f.backendDigest,
          policy_digest: f.entry.policy_digest,
          observed_at: observed,
        });
      } else assertEquals(res.status, fault === "malformed" ? 400 : 503);
      assertEquals(f.calls, []);
      assertEquals(
        calls,
        fault === "malformed"
          ? []
          : ["owner", "missing", "open", "other_attempt"].includes(fault)
          ? ["status"]
          : ["marker", "no_live_receipt"].includes(fault)
          ? ["status", "receipt"]
          : ["status", "receipt", "current"],
      );
    });
  }
});
