import { assertEquals, assertRejects } from "@std/assert";
import { attempt, fixture, owner } from "./fixtures.ts";
import { initialPhotoTransfer } from "./handler.ts";
import {
  closeInitialCpmPhotoWrite,
  type CpmWriteClosureDependencies,
  type CpmWriteClosureReceipt,
  snapshotCpmWriteClosureInput,
} from "../_shared/initialAnalysis/cpmPhotoWriteClosure.ts";

// Exercise the original assignment across issuance, a private byte observation
// and app-facing readback. No serving route, real signer, or storage is installed.
Deno.test("a fresh original earns app-visible progress only from its exact stored bytes", async (t) => {
  for (const fault of ["none", "changed_bytes", "lost_settlement_ack"]) {
    await t.step(fault, async () => {
      const submitted = new Uint8Array([1, 8, 3, 4]);
      const f = await fixture(0, submitted);
      const request = () => new Request("https://synthetic.invalid/transfer");
      const transfer = (body: unknown) =>
        initialPhotoTransfer(request(), body, owner, () => f.deps);
      const issue = await transfer(f.request);
      assertEquals(issue.status, 200);
      const ticket = await issue.json();
      assertEquals(ticket.outcome, "issued");
      assertEquals(ticket.attempt_id, attempt);
      const original = snapshotCpmWriteClosureInput(
        f.fresh.observation,
        attempt,
        "live_object",
      );
      const progress = {
        ...f.status,
        version: 2,
        action: "role_progress",
        attempt_id: attempt,
      };
      let receipt: Readonly<CpmWriteClosureReceipt> | null = null;
      let reads = 0, saves = 0;
      const deps: CpmWriteClosureDependencies = {
        bridge: {
          readReceipt(id, outcome) {
            assertEquals([id, outcome], [attempt, "live_object"]);
            return Promise.resolve(receipt);
          },
          load(id, outcome) {
            assertEquals([id, outcome], [attempt, "live_object"]);
            return Promise.resolve(original);
          },
          requireCurrent(value) {
            assertEquals(value, original);
            return Promise.resolve();
          },
          settle(value, claim) {
            assertEquals(claim, null);
            saves++;
            receipt = value;
            if (fault === "lost_settlement_ack") {
              throw new Error("lost local reply");
            }
            return Promise.resolve(value);
          },
        },
        storage: {
          sign: (_profile, req) => Promise.resolve(req),
          fetch(input, init) {
            const req = new Request(input, init);
            assertEquals(req.method, "GET");
            const observed = new URL(req.url), issued = new URL(ticket.url);
            assertEquals([observed.origin, observed.pathname], [
              issued.origin,
              issued.pathname,
            ]);
            reads++;
            const body = submitted.slice();
            if (fault === "changed_bytes") body[2] ^= 1;
            return Promise.resolve(
              new Response(body, {
                headers: {
                  "content-length": String(body.length),
                  "content-type": "image/jpeg",
                  "cache-control": "private, no-store",
                },
              }),
            );
          },
        },
      };
      f.deps.progress = {
        ...deps.bridge,
        async readStatus(...args) {
          const value = await f.deps.bridge.readStatus(...args);
          if (!value.attempt) throw new Error("original attempt missing");
          return {
            ...value,
            attempt: { ...value.attempt, write_closed: receipt !== null },
          };
        },
      };
      assertEquals((await transfer(progress)).status, 503);
      const observe = () =>
        closeInitialCpmPhotoWrite(
          deps,
          attempt,
          "live_object",
          request().signal,
        );
      if (fault === "changed_bytes") {
        await assertRejects(observe);
        assertEquals((await transfer(progress)).status, 503);
        assertEquals([reads, saves], [1, 0]);
      } else {
        assertEquals(
          (await observe()).outcome,
          fault === "none" ? "settled" : "replay",
        );
        const reply = await transfer(progress);
        assertEquals(reply.status, 200);
        const live = await reply.json();
        assertEquals([
          live.authority,
          live.object_id,
          live.attempt_id,
          live.role,
          live.byte_count,
          live.sha256,
        ], [
          "none",
          f.request.object_id,
          attempt,
          "source",
          submitted.length,
          f.fresh.observation.target.sha256,
        ]);
        assertEquals((await observe()).outcome, "replay");
        assertEquals([reads, saves], [1, 1]);
      }
      assertEquals(f.calls.filter((x) => x === "begin").length, 1);
    });
  }
});
