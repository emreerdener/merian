import { PublicationPhotoCohortContainerRejection } from "../_shared/analysisHistory/photoCohortPreflight.ts";
import { assert, assertEquals } from "@std/assert";
import type {
  PhotoClassifierProof,
  PhotoClassifierResult,
} from "../_shared/analysisHistory/photoClassifier.ts";
import type { RecoveredPhotoWork } from "../_shared/analysisHistory/publicationModerationRepository.ts";
import {
  moderatePublicationPhotos,
  type PublicationModerationDependencies,
} from "./handler.ts";
const id = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const source = {
  media_id: id(5),
  object_id: id(6),
  byte_count: 3,
  content_type: "image/jpeg",
  sha256: "a".repeat(64),
};
const scope = {
  owner_id: id(1),
  observation_id: id(2),
  operation_id: id(3),
  work_token: id(4),
};
const proof: PhotoClassifierProof = {
  schema_version: 1,
  policy_version: "photo_publication_v1",
  policy_sha256: "b".repeat(64),
  request_sha256: "c".repeat(64),
  provider: "gemini",
  model: "gemini-2.5-flash",
  processor_permission: "google_gemini",
  source,
};
const result: PhotoClassifierResult = {
  decision: "approved",
  classification: "allow",
  confidence: 0.99,
  categories: [],
  model: "gemini-2.5-flash",
  usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 },
};
function work(state: RecoveredPhotoWork["state"]): RecoveredPhotoWork {
  return {
    attempt_id: id(7),
    operation_id: id(3),
    media_id: id(5),
    state,
    lease_token: state === "reserved" || state === "dispatched" ? id(8) : null,
    dispatch_expires_at: state === "reserved" ? null : "2026-10-04T14:00:00Z",
    source,
    policy_version: "photo_publication_v1",
    provider: "gemini",
    model: "gemini-2.5-flash",
    processor_permission: "google_gemini",
  };
}
function fixture(initial: RecoveredPhotoWork | null = null) {
  const calls: string[] = [];
  let current = initial, elapsed = 0;
  const deps: PublicationModerationDependencies = {
    now: () => elapsed,
    list: () => {
      calls.push("list");
      return Promise.resolve([scope]);
    },
    claim: () => {
      calls.push("claim");
      return Promise.resolve({ scope, sources: [source] });
    },
    release: () => {
      calls.push("release");
      return Promise.resolve();
    },
    repository: (_claim, deadlines) => ({
      read: () => {
        calls.push("read");
        return Promise.resolve([current]);
      },
      finalize: () => {
        calls.push("finalize");
        return Promise.resolve(
          current !== null &&
            ["approved", "rejected", "cancelled", "unknown_execution"].includes(
              current.state,
            ),
        );
      },
      rejectContainer: () => {
        calls.push("rejectContainer");
        return Promise.resolve(true);
      },
      admit: () => {
        calls.push("admit");
        current = work("reserved");
        return Promise.resolve(current);
      },
      execution: () => ({
        saveProof: () => {
          calls.push("proof");
          return Promise.resolve();
        },
        dispatch: () => {
          calls.push("dispatch");
          if (!deadlines.canDispatch()) {
            throw new Error("insufficient provider window");
          }
          current = work("dispatched");
          return Promise.resolve(true);
        },
        complete: () => {
          calls.push("complete");
          assert(!deadlines.signal.aborted);
          current = work("approved");
          return Promise.resolve("approved");
        },
        retire: () => {
          calls.push("retire");
          if (current?.state === "dispatched") throw new Error("still live");
          current = work("cancelled");
          return Promise.resolve("cancelled");
        },
      }),
    }),
    preflight: () => {
      calls.push("preflight");
      return Promise.resolve({
        sources: [source],
        prepare: () => {
          calls.push("prepare");
          return Promise.resolve({
            proof,
            invoke: () => {
              calls.push("invoke");
              return Promise.resolve(result);
            },
          });
        },
      });
    },
  };
  return { deps, calls, clock: (n: number) => elapsed = n };
}
Deno.test("publication worker verifies full cohort and prepares before one paid admission", async () => {
  const f = fixture();
  assertEquals(await moderatePublicationPhotos(f.deps), {
    claimed: 1,
    settled: 1,
  });
  assertEquals(f.calls, [
    "list",
    "claim",
    "read",
    "finalize",
    "preflight",
    "prepare",
    "admit",
    "proof",
    "dispatch",
    "invoke",
    "complete",
    "finalize",
    "release",
  ]);
});
Deno.test("publication worker settles terminal recovery without external I/O or another attempt", async () => {
  for (
    const state of [
      "approved",
      "rejected",
      "cancelled",
      "unknown_execution",
    ] as const
  ) {
    const f = fixture(work(state));
    assertEquals(await moderatePublicationPhotos(f.deps), {
      claimed: 1,
      settled: 1,
    });
    assertEquals(f.calls, ["list", "claim", "read", "finalize", "release"]);
  }
});
Deno.test("publication worker dispatched recovery cannot invoke or refund a live provider", async () => {
  const f = fixture(work("dispatched"));
  assertEquals(await moderatePublicationPhotos(f.deps), {
    claimed: 1,
    settled: 0,
  });
  assertEquals(f.calls, [
    "list",
    "claim",
    "read",
    "finalize",
    "retire",
    "finalize",
    "release",
  ]);
});
Deno.test("publication worker reserved recovery repeats cohort verification without new quota", async () => {
  const f = fixture(work("reserved"));
  await moderatePublicationPhotos(f.deps);
  assert(f.calls.includes("preflight"));
  assert(f.calls.includes("invoke"));
  assert(!f.calls.includes("admit"));
});
Deno.test("publication worker preflight rejection cannot reserve or dispatch", async () => {
  const f = fixture();
  f.deps.preflight = () =>
    Promise.reject(new Error("private container detail"));
  assertEquals(await moderatePublicationPhotos(f.deps), {
    claimed: 1,
    settled: 0,
  });
  assertEquals(f.calls, ["list", "claim", "read", "finalize", "release"]);
});
Deno.test("publication worker refuses fresh admission when verification consumed its provider window", async () => {
  const f = fixture();
  const prepare = f.deps.preflight!;
  f.deps.preflight = async (...args) => {
    const value = await prepare(...args);
    f.clock(46_000);
    return value;
  };
  await moderatePublicationPhotos(f.deps);
  assert(!f.calls.includes("admit"));
  assert(!f.calls.includes("dispatch"));
  assert(f.calls.includes("release"));
});
Deno.test("publication worker cannot invoke after a lost dispatch acknowledgement", async () => {
  const f = fixture();
  const repo = f.deps.repository;
  f.deps.repository = (...args) => {
    const r = repo(...args);
    const execution = r.execution;
    r.execution = (w) => ({
      ...execution(w),
      dispatch: () => Promise.reject(new Error("uncertain")),
    });
    return r;
  };
  await moderatePublicationPhotos(f.deps);
  assert(!f.calls.includes("invoke"));
  assert(!f.calls.includes("retire"));
});
Deno.test("publication worker tries identical completion twice without invoking again", async () => {
  const f = fixture();
  const repo = f.deps.repository;
  f.deps.repository = (...args) => {
    const r = repo(...args);
    const execution = r.execution;
    r.execution = (w) => ({
      ...execution(w),
      complete: () => {
        f.calls.push("lost-completion");
        return Promise.reject(new Error("lost"));
      },
    });
    return r;
  };
  await moderatePublicationPhotos(f.deps);
  assertEquals(f.calls.filter((x) => x === "invoke").length, 1);
  assertEquals(f.calls.filter((x) => x === "lost-completion").length, 2);
  assert(!f.calls.includes("retire"));
});
Deno.test("publication worker claims only one candidate and tolerates release uncertainty", async () => {
  const f = fixture();
  f.deps.list = () =>
    Promise.resolve([scope, { ...scope, operation_id: id(9) }]);
  f.deps.release = () => Promise.reject(new Error("lost"));
  assertEquals(await moderatePublicationPhotos(f.deps), {
    claimed: 1,
    settled: 1,
  });
  assertEquals(f.calls.filter((x) => x === "claim").length, 1);
});

Deno.test("publication worker reserves dispatch latency before allowing a paid provider window", async () => {
  const f = fixture();
  const repo = f.deps.repository;
  f.deps.repository = (...args) => {
    const r = repo(...args);
    const execution = r.execution;
    r.execution = (w) => {
      const e = execution(w);
      return {
        ...e,
        saveProof: async (...p) => {
          await e.saveProof(...p);
          f.clock(79_000);
        },
      };
    };
    return r;
  };
  await moderatePublicationPhotos(f.deps);
  assert(!f.calls.includes("invoke"));
  assert(!f.calls.includes("complete"));
});

Deno.test("worker settles only typed verified container rejection without provider admission", async () => {
  const f = fixture();
  f.deps.preflight = () =>
    Promise.reject(new PublicationPhotoCohortContainerRejection(source));
  assertEquals(await moderatePublicationPhotos(f.deps), {
    claimed: 1,
    settled: 1,
  });
  assertEquals(f.calls, [
    "list",
    "claim",
    "read",
    "finalize",
    "rejectContainer",
    "release",
  ]);
});
Deno.test("worker does not settle a container rejection after completion budget is exhausted", async () => {
  const f = fixture();
  f.deps.preflight = () => {
    f.clock(124_000);
    return Promise.reject(new PublicationPhotoCohortContainerRejection(source));
  };
  assertEquals(await moderatePublicationPhotos(f.deps), {
    claimed: 1,
    settled: 0,
  });
  assert(!f.calls.includes("rejectContainer"));
  assert(!f.calls.includes("admit"));
});
