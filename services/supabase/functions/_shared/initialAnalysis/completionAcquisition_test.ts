import { completionAcquisitionFixture as fixture } from "./fixtures/completionAcquisition.ts";
import { assertEquals, assertRejects, assertThrows } from "@std/assert";
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { snapshotInitialCompletionAdmission } from "./completionAcquisition.ts";
import {
  createInitialCompletionAcquisition,
  createInitialResultStore,
} from "./resultStore.ts";

const options = {
  origin: "http://127.0.0.1",
  serverApiKey: ["sb", "secret", "fixture", "a".repeat(20)].join("_"),
};
const signal = () => new AbortController().signal;
Deno.test("first acquisition sends only saved admission and pins the discovered original for later exact recovery", async (t) => {
  for (const cpm of [true, false]) {
    await t.step(cpm ? "input_v2" : "input_v1", async () => {
      const f = await fixture(cpm), calls: string[] = [];
      const store = createInitialCompletionAcquisition({
        ...options,
        admission: f.admission,
        fetcher: (url, init) => {
          calls.push(String(url));
          assertEquals(JSON.parse(String(init?.body)), {
            p_owner: f.admission.owner_id,
            p_scan: f.admission.scan_id,
            p_admission: initialCanonicalText(f.admission),
          });
          assertEquals(init?.redirect, "error");
          assertEquals(init?.credentials, "omit");
          assertEquals(init?.cache, "no-store");
          return Promise.resolve(Response.json(f.reply));
        },
      });
      const acquired = await store.read(signal());
      assertEquals(acquired?.reference, f.evidence.reference);
      assertEquals(acquired?.delivery.result, f.evidence);
      assertEquals(calls, [
        "http://127.0.0.1/rest/v1/rpc/discover_initial_completion_v1",
      ]);
      if (!acquired) {
        throw new Error("missing");
      }
      const a = acquired.admission;
      const pinned = createInitialResultStore({
        ...options,
        reference: acquired.reference,
        originalProvenanceCanonical: acquired.original_provenance_canonical,
        completionBinding: {
          route: a.route,
          input_schema_version: a.input_schema_version,
          funding_binding_id: a.funding_binding_id,
          funding_binding_version: a.funding_binding_version,
          ordered_description_digest: a.ordered_description_digest,
          ordered_description_count: a.ordered_description_count,
        },
        fetcher: () => Promise.resolve(Response.json(f.delivery)),
      });
      assertEquals(
        await pinned.readCompletion({
          ...acquired.reference,
          result_digest: acquired.result_digest,
        }, signal()),
        acquired.delivery,
      );
      await assertRejects(() =>
        pinned.readCompletion({
          ...acquired.reference,
          result_digest: "f".repeat(64),
        }, signal())
      );
    });
  }
});
Deno.test("acquisition only accepts explicit empty pending and never retries or writes", async () => {
  const f = await fixture();
  let calls = 0;
  const pending = {
    ...f.reply,
    outcome: "pending",
    reference: null,
    result_digest: null,
    original_provenance: null,
    delivery: null,
  };
  const store = createInitialCompletionAcquisition({
    ...options,
    admission: f.admission,
    fetcher: () => {
      calls++;
      return Promise.resolve(Response.json(pending));
    },
  });
  assertEquals(await store.read(signal()), null);
  assertEquals(calls, 1);
});
Deno.test("acquisition rejects conflicting admission, independently retained origin and nested completion", async (t) => {
  for (
    const mode of [
      "admission",
      "version",
      "reference",
      "digest",
      "provenance",
      "receipt",
      "extra",
      "pending_payload",
      "found_absent",
    ]
  ) {
    await t.step(mode, async () => {
      const f = await fixture();
      const reply = structuredClone(f.reply);
      let calls = 0;
      if (mode === "admission") {
        reply.admission_canonical = initialCanonicalText({
          ...f.admission,
          input_schema_version: 1,
        });
      }
      if (mode === "version") reply.version = 2;
      if (mode === "reference") {
        reply.reference = { ...reply.reference, config_digest: "f".repeat(64) };
      }
      if (mode === "digest") reply.result_digest = "f".repeat(64);
      if (mode === "provenance") reply.original_provenance = {};
      if (mode === "receipt") {
        reply.delivery.completion.receipt_canonical = initialCanonicalText({
          ...parseInitialCanonicalText(
            reply.delivery.completion.receipt_canonical,
          ) as object,
          config_digest: "f".repeat(64),
        });
      }
      if (mode === "extra") Reflect.set(reply, "authority", true);
      if (mode === "pending_payload") reply.outcome = "pending";
      if (mode === "found_absent") {
        Object.assign(reply.delivery, {
          outcome: "absent",
          completion: null,
          result: null,
        });
      }
      const store = createInitialCompletionAcquisition({
        ...options,
        admission: f.admission,
        fetcher: () => {
          calls++;
          return Promise.resolve(Response.json(reply));
        },
      });
      await assertRejects(() => store.read(signal()));
      assertEquals(calls, 1);
    });
  }
});
Deno.test("acquisition snapshots admission and fails closed on unsupported versions or accessor input", async () => {
  const f = await fixture();
  const mutable = { ...f.admission };
  const store = createInitialCompletionAcquisition({
    ...options,
    admission: mutable,
    fetcher: () => Promise.resolve(Response.json(f.reply)),
  });
  mutable.input_schema_version = 1;
  assertEquals((await store.read(signal()))?.admission.input_schema_version, 2);
  assertThrows(() =>
    snapshotInitialCompletionAdmission({
      ...f.admission,
      input_schema_version: 3,
    })
  );
  let reads = 0;
  const getter = { ...f.admission };
  Object.defineProperty(getter, "config_digest", {
    enumerable: true,
    get() {
      reads++;
      return f.admission.config_digest;
    },
  });
  assertThrows(() => snapshotInitialCompletionAdmission(getter));
  assertEquals(reads, 0);
});
Deno.test("lost, cancelled and oversized acquisition replies remain uncertain without retry", async (t) => {
  for (const mode of ["lost", "cancel", "oversize"]) {
    await t.step(mode, async () => {
      const f = await fixture();
      let calls = 0;
      const controller = new AbortController();
      const store = createInitialCompletionAcquisition({
        ...options,
        admission: f.admission,
        fetcher: () => {
          calls++;
          if (mode === "lost") {
            return Promise.reject(new Error("lost synthetic reply"));
          }
          if (mode === "cancel") controller.abort();
          return Promise.resolve(
            mode === "oversize"
              ? new Response("x".repeat(2541569))
              : Response.json(f.reply),
          );
        },
      });
      await assertRejects(() => store.read(controller.signal));
      assertEquals(calls, 1);
    });
  }
});
