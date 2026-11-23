import { assertEquals, assertRejects } from "@std/assert";
import type { R2Config } from "../_shared/aws.ts";
import { captureObjectBackendDigest } from "../_shared/captureObjectRetirement.ts";
import { PrivateEvidenceErasureStorage } from "./storage.ts";

Deno.test("typed erasure never redirects a stage marker to another backend or History namespace", async () => {
  const config = {
    endpoint: "https://synthetic.invalid",
    bucketName: "synthetic-private",
  } as R2Config;
  const backend = await captureObjectBackendDigest(config),
    calls: string[] = [];
  const storage = new PrivateEvidenceErasureStorage(
    {
      erase: (object) => {
        calls.push(`history:${object}`);
        return Promise.resolve();
      },
    },
    () => config,
    (saved) => {
      assertEquals(saved, config);
      return {
        erase: (object) => {
          calls.push(`stage:${object}`);
          return Promise.resolve();
        },
      };
    },
  );
  const signal = new AbortController().signal;
  await storage.erase("same-object", signal, {
    namespace: "history",
    backend_sha256: null,
  });
  await storage.erase("same-object", signal, {
    namespace: "capture_stage",
    backend_sha256: backend,
  });
  for (const bad of [null, "a".repeat(64), "invalid"]) {
    await assertRejects(() =>
      storage.erase("same-object", signal, {
        namespace: "capture_stage",
        backend_sha256: bad,
      })
    );
  }
  await assertRejects(() =>
    storage.erase("same-object", signal, {
      namespace: "history",
      backend_sha256: backend,
    })
  );
  assertEquals(calls, ["history:same-object", "stage:same-object"]);
  const aborted = new AbortController();
  aborted.abort();
  await assertRejects(() =>
    storage.erase("same-object", aborted.signal, {
      namespace: "capture_stage",
      backend_sha256: backend,
    })
  );
  assertEquals(calls.length, 2);
});
