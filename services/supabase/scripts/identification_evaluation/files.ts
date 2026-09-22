import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import type { SourceIdentity } from "./runContracts.ts";
import { requireCondition as check } from "./validation.ts";

/** Local files only; callers receive fixed error codes at the CLI boundary. */
export async function readBytes(
  path: string,
  limit: number,
): Promise<Uint8Array> {
  const before = await Deno.lstat(path);
  check(before.isFile && !before.isSymlink && before.nlink === 1);
  check(before.size > 0 && before.size <= limit);
  using file = await Deno.open(path, { read: true });
  const opened = await file.stat();
  check(
    opened.ino === before.ino && opened.dev === before.dev &&
      opened.size === before.size,
  );
  const bytes = new Uint8Array(before.size);
  let offset = 0;
  while (offset < bytes.length) {
    const count = await file.read(bytes.subarray(offset));
    check(count !== null && count > 0);
    offset += count;
  }
  check(await file.read(new Uint8Array(1)) === null);
  const after = await file.stat();
  check(
    after.size === before.size &&
      after.mtime?.getTime() === before.mtime?.getTime(),
  );
  return bytes;
}
export async function readJson(
  path: string,
  limit = 4 * 1024 * 1024,
): Promise<unknown> {
  return JSON.parse(
    new TextDecoder("utf-8", { fatal: true }).decode(
      await readBytes(path, limit),
    ),
  );
}
export async function exists(path: string): Promise<boolean> {
  try {
    await Deno.lstat(path);
    return true;
  } catch (e) {
    if (e instanceof Deno.errors.NotFound) return false;
    throw e;
  }
}
export async function syncDirectory(path: string): Promise<void> {
  using directory = await Deno.open(path, { read: true });
  await directory.sync();
}
export async function privateDirectory(path: string): Promise<string> {
  if (!await exists(path)) {
    await Deno.mkdir(path, { mode: 0o700 });
    await syncDirectory(dirname(path));
  }
  const stat = await Deno.lstat(path);
  check(
    stat.isDirectory && !stat.isSymlink && stat.mode !== null &&
      (stat.mode & 0o077) === 0,
  );
  return await Deno.realPath(path);
}
export async function containedPath(
  root: string,
  path: string,
): Promise<string> {
  check(!isAbsolute(path));
  const rel = relative(root, resolve(root, path));
  check(rel !== "" && !rel.startsWith("..") && !isAbsolute(rel));
  let current = root;
  for (const component of rel.split("/")) {
    current = join(current, component);
    check(!(await Deno.lstat(current)).isSymlink);
  }
  return current;
}

async function writeFlushed(path: string, bytes: Uint8Array): Promise<void> {
  using file = await Deno.open(path, {
    write: true,
    createNew: true,
    mode: 0o600,
  });
  let offset = 0;
  while (offset < bytes.length) {
    const n = await file.write(bytes.subarray(offset));
    check(n > 0);
    offset += n;
  }
  await file.sync();
}
/** Immutable claims use createNew. A torn claim fails closed on restart. */
export async function claimJson(path: string, value: unknown): Promise<void> {
  await writeFlushed(
    path,
    new TextEncoder().encode(JSON.stringify(value) + "\n"),
  );
  await syncDirectory(dirname(path));
}
/** A directory flush is part of success, never a best-effort extra. */
export async function atomicText(path: string, value: string): Promise<void> {
  const temp = `${path}.${crypto.randomUUID()}.tmp`;
  await writeFlushed(temp, new TextEncoder().encode(value));
  await Deno.rename(temp, path);
  await syncDirectory(dirname(path));
}
export function atomicJson(path: string, value: unknown): Promise<void> {
  return atomicText(path, JSON.stringify(value, null, 2) + "\n");
}
/** The persistent inode must never be deleted to "unlock" a running process. */
export async function withRunLock<T>(
  root: string,
  work: () => Promise<T>,
): Promise<T> {
  const path = join(root, ".lock");
  if (await exists(path)) {
    const stat = await Deno.lstat(path);
    check(stat.isFile && !stat.isSymlink && stat.nlink === 1);
  }
  using file = await Deno.open(path, {
    read: true,
    write: true,
    create: true,
    mode: 0o600,
  });
  check(await file.tryLock(true));
  try {
    return await work();
  } finally {
    await file.unlock();
  }
}

/** Hash the complete local implementation graph, including dirty/untracked code. */
export async function sourceIdentity(
  repository: string,
): Promise<SourceIdentity> {
  const git = async (args: string[]) => {
    const r = await new Deno.Command("git", {
      args: [
        "-c",
        "core.fsmonitor=false",
        "-c",
        "core.hooksPath=/dev/null",
        "-C",
        repository,
        ...args,
      ],
      stdout: "piped",
      stderr: "null",
    }).output();
    check(r.success);
    return new TextDecoder().decode(r.stdout).trim();
  };
  const items: { path: string; digest: string }[] = [];
  async function walk(path: string): Promise<void> {
    for await (const entry of Deno.readDir(join(repository, path))) {
      check(!entry.isSymlink);
      const child = `${path}/${entry.name}`;
      if (entry.isDirectory) await walk(child);
      else if (/\.(ts|json|lock|sh)$/.test(entry.name)) {
        items.push({
          path: child,
          digest: await fingerprintBytes(
            await readBytes(join(repository, child), 8 * 1024 * 1024),
          ),
        });
      }
    }
  }
  await walk("services/supabase/functions");
  await walk("services/supabase/scripts");
  items.sort((a, b) => a.path.localeCompare(b.path));
  const config = await readJson(
    join(repository, "services/supabase/functions/deno.json"),
  ) as { imports: Record<string, string> };
  return {
    commit: await git(["rev-parse", "HEAD"]),
    dirty:
      (await git(["status", "--porcelain", "--untracked-files=all"])) !== "",
    digest: await fingerprintJson(items),
    sdk: config.imports["@google/genai"],
  };
}
