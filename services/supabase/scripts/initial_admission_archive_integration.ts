import { assert, assertEquals, assertRejects } from "@std/assert";
import vectors from "../functions/_shared/initialAnalysis/fixtures/admission-v1.json" with {
  type: "json",
};
import catalog from "../functions/_shared/initialAnalysis/configuration-assets-v1.json" with {
  type: "json",
};
import { prepareInitialAdmission } from "../functions/_shared/initialAnalysis/preparation.ts";
import { InitialAnalysisLifecycleRepository } from "../functions/_shared/initialAnalysis/repository.ts";
import {
  createInitialAdmissionTransport,
  type InitialAssetReader,
} from "../functions/_shared/initialAnalysis/transport.ts";
import { resolveInitialSourceArchive } from "../functions/_shared/initialAnalysis/sourceArchive.ts";
import { buildInitialSourceArchiveFromGit } from "./build_initial_source_archive.ts";
import { repoRoot } from "./function_dependency_tools.ts";

const signal = () => new AbortController().signal;
const key = ["sb", "secret", "fixture", "a".repeat(20)].join("_");
const origin = "https://project.supabase.co";
const owner = "00000000-0000-4000-8000-00000000b001";
const scan = "00000000-0000-4000-8000-00000000b002";
const input = vectors.valid[0];
const unknown = {
  outcome: "unknown",
  reason: "write_outcome_unknown",
} as const;
const unavailable = {
  outcome: "held",
  reason: "configuration_unavailable",
} as const;

// Build and verify the saved revision before the bounded admission starts.
// No current-checkout dependency/configuration bytes supply archived authority.
const bytes = await buildInitialSourceArchiveFromGit(repoRoot, signal());
const archive = await resolveInitialSourceArchive(
  new Blob([bytes]).stream(),
  catalog.digest,
  signal(),
);
const assetReader: InitialAssetReader = archive.readAsset;
const binding = {
  version: 1 as const,
  owner_id: owner,
  scan_id: scan,
  route: input.input.route,
  submission_digest: input.digest,
  configuration_digest: "a".repeat(64),
  funding_digest: "b".repeat(64),
  descriptions_digest: "c".repeat(64),
  funding_binding_id: "00000000-0000-4000-8000-00000000b003",
  assets_digest: catalog.digest,
};
function repository(
  fetcher: typeof fetch,
  read: InitialAssetReader = assetReader,
) {
  return new InitialAnalysisLifecycleRepository(
    createInitialAdmissionTransport(origin, key, fetcher),
    read,
  );
}
function recover(repo: InitialAnalysisLifecycleRepository, caller = signal()) {
  return repo.recoverAdmission(
    owner,
    scan,
    input.canonical,
    input.digest,
    caller,
  );
}
function deferred<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((r) => {
    resolve = r;
  });
  return { promise, resolve };
}

Deno.test("IC-1 unknown admission performs one write and recovery cannot allocate or dispatch", async () => {
  const initial = await prepareInitialAdmission(vectors.valid[0].input);
  const owner = "00000000-0000-4000-8000-00000000a001",
    scan = "00000000-0000-4000-8000-00000000a002";
  let calls = 0;
  const requests: Record<string, unknown>[] = [];
  const repository = new InitialAnalysisLifecycleRepository(
    createInitialAdmissionTransport(
      "https://project.supabase.co",
      key,
      (_url, init) => {
        const args = JSON.parse(init!.body as string);
        calls++;
        requests.push(args);
        return Promise.reject(new Error("lost acknowledgement"));
      },
    ),
    assetReader,
  );
  assertEquals(
    await repository.admit(owner, scan, initial, "a".repeat(64), signal()),
    {
      outcome: "unknown",
      reason: "write_outcome_unknown",
    },
  );
  assertEquals(calls, 1);
  assertEquals(
    await repository.recoverAdmission(
      owner,
      scan,
      initial.canonicalInput,
      initial.submissionDigest,
      signal(),
    ),
    { outcome: "unknown", reason: "write_outcome_unknown" },
  );
  assertEquals(calls, 2);
  assertEquals(requests[1].p_assets_digest, null);
  assertEquals(requests[1].p_ip_hash, null);
  assertEquals(requests[0].p_canonical_input, requests[1].p_canonical_input);
  await assertRejects(() =>
    repository.admit(owner, scan, { ...initial }, "a".repeat(64), signal())
  );
});
Deno.test("IC-1 cancellation after final asset prevents write", async () => {
  const caller = new AbortController();
  let network = 0, reachedFinalAsset = false;
  const repo = repository(() => {
    network++;
    throw new Error("network");
  }, async (path, revision, supplied) => {
    const stream = await assetReader(path, revision, supplied);
    if (path === catalog.manifest.files.at(-1)!.path) {
      reachedFinalAsset = true;
      caller.abort();
    }
    return stream;
  });
  assertEquals(
    await repo.admit(
      owner,
      scan,
      await prepareInitialAdmission(input.input),
      "a".repeat(64),
      caller.signal,
    ),
    unavailable,
  );
  assert(reachedFinalAsset);
  assertEquals(network, 0);
});

Deno.test("IC-1 lost committed admission reply stays unknown and exact recovery skips assets", async () => {
  const caller = new AbortController();
  const issued = deferred<void>();
  const late = deferred<Response>();
  let calls = 0, reads = 0, cancelled = false;
  const requests: Record<string, unknown>[] = [];
  const repo = repository((_url, init) => {
    requests.push(JSON.parse(init!.body as string));
    calls++;
    if (calls === 1) {
      issued.resolve();
      return late.promise;
    }
    return Promise.resolve(Response.json({ outcome: "replay", binding }));
  }, (path, revision, supplied) => {
    reads++;
    return assetReader(path, revision, supplied);
  });
  const pending = repo.admit(
    owner,
    scan,
    await prepareInitialAdmission(input.input),
    "a".repeat(64),
    caller.signal,
  );
  await Promise.race([
    issued.promise,
    pending.then(() => {
      throw new Error("admission settled before issuing its write");
    }),
  ]);
  caller.abort();
  assertEquals(await pending, unknown);
  const count = reads;
  late.resolve(
    new Response(
      new ReadableStream({
        cancel() {
          cancelled = true;
        },
      }),
    ),
  );
  await new Promise((r) => setTimeout(r, 0));
  assert(cancelled);
  assertEquals(calls, 1);
  assertEquals(await recover(repo), { outcome: "replay", binding });
  assertEquals(calls, 2);
  assertEquals(reads, count);
  assertEquals(requests[1], {
    ...requests[0],
    p_assets_digest: null,
    p_ip_hash: null,
  });
});
