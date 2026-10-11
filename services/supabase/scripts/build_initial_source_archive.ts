import { join } from "node:path";
import catalog from "../functions/_shared/initialAnalysis/configuration-assets-v1.json" with {
  type: "json",
};
import {
  buildInitialSourceArchive,
  INITIAL_SOURCE_ARCHIVE_BYTES,
  resolveInitialSourceArchive,
} from "../functions/_shared/initialAnalysis/sourceArchive.ts";
import {
  checkInitialDeadline,
  INITIAL_ASSET_BYTES,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "../functions/_shared/initialAnalysis/transport.ts";
import { repoRoot } from "./function_dependency_tools.ts";

const unavailable = () =>
  new Error("initial_analysis_source_archive_build_failed");
const streamOf = (bytes: Uint8Array) =>
  new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes);
      controller.close();
    },
  });

async function gitBytes(
  repository: string,
  args: string[],
  limit: number,
  signal: AbortSignal,
): Promise<Uint8Array<ArrayBuffer>> {
  checkInitialDeadline(signal);
  // No filters, replacement objects, working-tree reads, network or shell.
  const child = new Deno.Command("git", {
    args: ["--no-replace-objects", "-C", repository, ...args],
    stdin: "null",
    stdout: "piped",
    stderr: "null",
  }).spawn();
  const kill = () => {
    try {
      child.kill("SIGKILL");
    } catch { /* already exited */ }
  };
  signal.addEventListener("abort", kill, { once: true });
  try {
    const bytes = await readInitialStream(child.stdout, limit, signal);
    const status = await initialAbortable(signal, () => child.status);
    if (!status.success) throw unavailable();
    return bytes;
  } finally {
    signal.removeEventListener("abort", kill);
    kill();
    // Reap the owned child after success, failure or cancellation.
    void child.status.catch(() => {});
  }
}

export async function buildInitialSourceArchiveFromGit(
  repository: string,
  caller: AbortSignal,
): Promise<Uint8Array<ArrayBuffer>> {
  return await initialDeadline(caller, 60_000, async (signal) => {
    const revision = catalog.manifest.repository_revision;
    const paths = catalog.manifest.files.map((entry) => entry.path);
    const tree = new TextDecoder("utf-8", { fatal: true }).decode(
      await gitBytes(
        repository,
        ["ls-tree", "-z", revision, "--", ...paths],
        32_768,
        signal,
      ),
    );
    const records = tree.split("\0");
    if (records.pop() !== "" || records.length !== paths.length) {
      throw unavailable();
    }
    const found = new Set<string>();
    for (const record of records) {
      const match = /^(100644|100755) blob [0-9a-f]{40}\t(.+)$/.exec(record);
      if (!match || !paths.includes(match[2]) || found.has(match[2])) {
        throw unavailable();
      }
      found.add(match[2]);
    }
    return await buildInitialSourceArchive(
      async (path, savedRevision, readSignal) => {
        if (savedRevision !== revision || !found.has(path)) throw unavailable();
        return streamOf(
          await gitBytes(
            repository,
            ["cat-file", "blob", `${revision}:${path}`],
            INITIAL_ASSET_BYTES,
            readSignal,
          ),
        );
      },
      signal,
    );
  });
}

/** Atomic no-replace publication in an operator-owned local directory. An
 * interrupted temporary write cannot replace an existing complete artifact.
 * Filesystem calls are not preemptible: cancellation is checked between them,
 * not a wall-clock publication guarantee. This is not hosted retention or a
 * power-loss durability qualification. */
export async function publishInitialSourceArchive(
  bytes: Uint8Array,
  directory: string,
  caller: AbortSignal,
): Promise<string> {
  const frozen = new Uint8Array(bytes);
  const verified = await resolveInitialSourceArchive(
    streamOf(frozen),
    catalog.digest,
    caller,
  );
  const info = await Deno.lstat(directory);
  if (!info.isDirectory || info.isSymlink) throw unavailable();
  const destination = join(directory, `${verified.archiveSha256}.json`);
  const temporary = join(
    directory,
    `.initial-source-${crypto.randomUUID()}.tmp`,
  );
  checkInitialDeadline(caller);
  const file = await Deno.open(temporary, {
    write: true,
    createNew: true,
    mode: 0o600,
  });
  try {
    let offset = 0;
    while (offset < frozen.length) {
      checkInitialDeadline(caller);
      const count = await file.write(frozen.subarray(offset));
      if (count === 0) throw unavailable();
      offset += count;
    }
    await file.sync();
    checkInitialDeadline(caller);
    try {
      await Deno.link(temporary, destination);
    } catch (error) {
      if (!(error instanceof Deno.errors.AlreadyExists)) throw error;
      const existingInfo = await Deno.lstat(destination);
      if (
        !existingInfo.isFile || existingInfo.isSymlink ||
        existingInfo.size !== frozen.length
      ) throw unavailable();
      const existing = await Deno.open(destination, { read: true });
      try {
        const current = await resolveInitialSourceArchive(
          existing.readable,
          catalog.digest,
          caller,
        );
        if (current.archiveSha256 !== verified.archiveSha256) {
          throw unavailable();
        }
      } finally {
        // FsFile.readable normally closes at EOF/cancel; also cover early
        // validation failure before acquiring the reader.
        try {
          existing.close();
        } catch { /* The file-readable may already have closed the handle. */ }
      }
    }
    checkInitialDeadline(caller);
    return verified.archiveSha256;
  } finally {
    file.close();
    await Deno.remove(temporary);
  }
}

if (import.meta.main) {
  try {
    if (Deno.args.length !== 1) throw unavailable();
    const caller = AbortSignal.timeout(75_000);
    const bytes = await buildInitialSourceArchiveFromGit(repoRoot, caller);
    if (bytes.length > INITIAL_SOURCE_ARCHIVE_BYTES) throw unavailable();
    const archive = await publishInitialSourceArchive(
      bytes,
      Deno.args[0],
      caller,
    );
    console.log(
      JSON.stringify({
        format_version: 1,
        archive_sha256: archive,
        asset_manifest_digest: catalog.digest,
        byte_count: bytes.length,
      }),
    );
  } catch {
    console.error(
      "Initial source archive build failed; no executable or activation proof was produced.",
    );
    Deno.exitCode = 1;
  }
}
