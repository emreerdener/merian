import { assertEquals, assertRejects } from "@std/assert";
import { initialCanonicalText } from "./canonical.ts";
import { snapshotInitialCompletionDocuments } from "./completionContract.ts";

import { id, projection, receipt } from "./fixtures/completionDocuments.ts";

Deno.test("completion decoder preserves both media variants and all three settlement outcomes", async (t) => {
  for (const cpm of [true, false]) {
    for (
      const outcome of [
        "none",
        "consumed_durable_result",
        "released_paid_before_completion",
      ]
    ) {
      await t.step(`${cpm ? "CPM" : "legacy"}/${outcome}`, async () => {
        const p = projection(cpm, outcome), r = await receipt(p);
        const result = await snapshotInitialCompletionDocuments(r, p);
        assertEquals(result.projection_canonical, initialCanonicalText(p));
        assertEquals(result.receipt_canonical, initialCanonicalText(r));
      });
    }
  }
});

Deno.test("completion decoder enforces the JSONB byte ceiling as well as canonical bytes", async () => {
  const p = projection();
  p.species_association = { species_id: id(8), scientific_name: "" };
  const postgresText = (value: unknown): string => {
    if (Array.isArray(value)) return `[${value.map(postgresText).join(", ")}]`;
    if (value !== null && typeof value === "object") {
      return `{${
        Object.entries(value).map(([key, child]) =>
          `${JSON.stringify(key)}: ${postgresText(child)}`
        ).join(", ")
      }}`;
    }
    return JSON.stringify(value);
  };
  const available = 65536 - new TextEncoder().encode(postgresText(p)).length;
  p.species_association.scientific_name = "x".repeat(available);
  await snapshotInitialCompletionDocuments(await receipt(p), p);
  p.species_association.scientific_name += "x";
  assertEquals(
    new TextEncoder().encode(initialCanonicalText(p)).length < 65536,
    true,
  );
  await assertRejects(async () =>
    snapshotInitialCompletionDocuments(await receipt(p), p)
  );
});

Deno.test("completion decoder rejects unknown and omitted keys throughout immutable documents", async (t) => {
  const p = projection(), r = await receipt(p);
  const paths = [
    [],
    ["settlement"],
    ["entitlement_after"],
    ["capture_context"],
    ["media"],
    ["media", "items", 0],
  ];
  for (const path of paths) {
    for (const mode of ["extra", "missing"]) {
      await t.step(`${path.join("/")}/${mode}`, async () => {
        const copy = structuredClone(p);
        let target: unknown = copy;
        for (const key of path) target = Reflect.get(target as object, key);
        if (mode === "extra") Reflect.set(target as object, "unexpected", true);
        else {Reflect.deleteProperty(
            target as object,
            Object.keys(target as object)[0],
          );}
        await assertRejects(() => snapshotInitialCompletionDocuments(r, copy));
      });
    }
  }
  for (const key of Object.keys(r)) {
    const copy = { ...r };
    Reflect.deleteProperty(copy, key);
    await assertRejects(() => snapshotInitialCompletionDocuments(copy, p));
  }
  await assertRejects(() =>
    snapshotInitialCompletionDocuments({ ...r, unexpected: true }, p)
  );
});

Deno.test("completion decoder rejects inconsistent identity, settlement, chronology and media even with a recomputed digest", async (t) => {
  const mutations: Record<string, (p: ReturnType<typeof projection>) => void> =
    {
      owner: (p) => {
        p.owner_id = id(9);
      },
      result: (p) => {
        p.result_evidence_id = id(9);
      },
      submission: (p) => {
        p.capture_context.submission_digest = "b".repeat(64);
      },
      transfer: (p) => {
        p.media.receipt_digest = "b".repeat(64);
      },
      credit: (p) => {
        p.credit_consumed = false;
      },
      settlement: (p) => {
        p.settlement.settled_at = null;
      },
      clock: (p) => {
        p.completed_at = "2026-02-31T03:00:00+00:00";
        p.scan_timestamp = p.completed_at;
      },
      timestamp: (p) => {
        p.scan_timestamp = "2026-11-03T03:00:00+00:00";
      },
      privacy: (p) => {
        p.geoprivacy = "open";
      },
      source: (p) => {
        p.capture_context.source = "legacy_input_v1";
      },
      ordinal: (p) => {
        p.media.items[0].ordinal = 1;
      },
      duplicate: (p) => {
        p.media.items.push({ ...p.media.items[0], ordinal: 1 });
      },
      empty: (p) => {
        p.media.items = [];
      },
      format: (p) => {
        p.media.items[0].content_type = "image/png";
      },
      bytes: (p) => {
        p.media.items[0].byte_count = 4194305;
      },
      poster: (p) => {
        p.media.items[0].poster_media_id = id(9);
      },
      quota: (p) => {
        p.entitlement_after.scans_remaining = 4;
      },
    };
  for (const [name, mutate] of Object.entries(mutations)) {
    await t.step(name, async () => {
      const p = projection();
      mutate(p);
      await assertRejects(async () =>
        snapshotInitialCompletionDocuments(await receipt(p), p)
      );
    });
  }
});

Deno.test("completion decoder snapshots before suspension and rejects changed digest, accessors and oversized documents", async () => {
  const p = projection(), r = await receipt(p);
  const original = initialCanonicalText(p);
  const pending = snapshotInitialCompletionDocuments(r, p);
  p.credit_consumed = false;
  assertEquals((await pending).projection_canonical, original);
  const good = projection();
  await assertRejects(() =>
    snapshotInitialCompletionDocuments({
      ...r,
      completion_projection_digest: "b".repeat(64),
    }, good)
  );
  const getter = { ...good };
  Object.defineProperty(getter, "completed_at", {
    enumerable: true,
    get() {
      throw new Error("must not evaluate");
    },
  });
  await assertRejects(() => snapshotInitialCompletionDocuments(r, getter));
  await assertRejects(() =>
    snapshotInitialCompletionDocuments(r, {
      ...good,
      species_association: {
        species_id: id(8),
        scientific_name: "x".repeat(65536),
      },
    })
  );
});
