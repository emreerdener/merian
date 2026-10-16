import { assert, assertEquals, assertRejects } from "@std/assert";
import { join } from "node:path";
import catalog from "../functions/_shared/initialAnalysis/configuration-assets-v1.json" with {
  type: "json",
};
import {
  buildInitialSourceArchive,
  INITIAL_SOURCE_ARCHIVE_BYTES,
  resolveInitialSourceArchive,
} from "../functions/_shared/initialAnalysis/sourceArchive.ts";
import { verifyInitialConfigurationAssets } from "../functions/_shared/initialAnalysis/configuration.ts";
import {
  INITIAL_ASSET_BYTES,
  readInitialStream,
} from "../functions/_shared/initialAnalysis/transport.ts";
import {
  buildInitialSourceArchiveFromGit,
  publishInitialSourceArchive,
} from "./build_initial_source_archive.ts";
import { repoRoot } from "./function_dependency_tools.ts";

const root = Deno.args[0];
const signal = () => new AbortController().signal;
const encoder = new TextEncoder();
const stream = (bytes: Uint8Array) =>
  new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(bytes);
      c.close();
    },
  });
const load = (bytes: Uint8Array, digest = catalog.digest, caller = signal()) =>
  resolveInitialSourceArchive(stream(bytes), digest, caller);
const command = async (...args: string[]) => {
  const result = await new Deno.Command("git", {
    args,
    stdout: "null",
    stderr: "null",
  }).output();
  assertEquals(result.code, 0);
};

Deno.test("initial source archive: exact Git bytes, closed resolver and atomic local publication", async (t) => {
  assert(root, "isolated directory required");
  const bytes = await buildInitialSourceArchiveFromGit(repoRoot, signal());
  const baseline = new TextDecoder().decode(bytes);
  const archive = await load(bytes);
  const clone = join(root, "checkout");
  const output = join(root, "archives");
  await Deno.mkdir(output);
  await command(
    "clone",
    "--shared",
    "--no-checkout",
    "--quiet",
    repoRoot,
    clone,
  );

  await t.step(
    "dirty checkout and missing worktree files cannot affect exact deterministic output",
    async () => {
      const changed = join(
        clone,
        "services/supabase/functions/_shared/audioProcessing.ts",
      );
      await Deno.mkdir(join(clone, "services/supabase/functions/_shared"), {
        recursive: true,
      });
      await Deno.writeTextFile(
        changed,
        "throw new Error('synthetic changed preprocessing');\n",
      );
      assertEquals(
        await buildInitialSourceArchiveFromGit(clone, signal()),
        bytes,
      );
    },
  );
  await t.step(
    "complete verified archive satisfies current asset verifier",
    async () => {
      await verifyInitialConfigurationAssets(archive.readAsset, signal());
      assertEquals(archive.assetManifestDigest, catalog.digest);
      assert(archive.archiveSha256 !== archive.assetManifestDigest);
    },
  );
  await t.step("consumer mutation does not alter retained bytes", async () => {
    const file = catalog.manifest.files[0];
    const first = await readInitialStream(
      await archive.readAsset(
        file.path,
        catalog.manifest.repository_revision,
        signal(),
      ),
      INITIAL_ASSET_BYTES,
      signal(),
    );
    first.fill(0);
    await verifyInitialConfigurationAssets(archive.readAsset, signal());
  });
  await t.step(
    "unknown paths, revisions, catalog digests and pre-aborted reads hold",
    async () => {
      for (
        const path of [
          "../dependencies.lock",
          "/tmp/asset",
          catalog.manifest.files[0].path + "/../provider.ts",
        ]
      ) {
        await assertRejects(async () =>
          await archive.readAsset(
            path,
            catalog.manifest.repository_revision,
            signal(),
          )
        );
      }
      await assertRejects(async () =>
        await archive.readAsset(
          catalog.manifest.files[0].path,
          "HEAD",
          signal(),
        )
      );
      await assertRejects(() => load(bytes, "0".repeat(64)));
      await assertRejects(() =>
        load(bytes, catalog.digest, AbortSignal.abort())
      );
      await assertRejects(async () =>
        await archive.readAsset(
          catalog.manifest.files[0].path,
          catalog.manifest.repository_revision,
          AbortSignal.abort(),
        )
      );
    },
  );
  const mutations: [string, (v: Record<string, unknown>) => void][] = [
    ["wrong format", (v) => v.format_version = 2],
    ["unknown field", (v) => v.extra = true],
    [
      "changed revision",
      (v) =>
        (v.catalog as typeof catalog).manifest.repository_revision = "0".repeat(
          40,
        ),
    ],
    [
      "changed lock inventory",
      (v) => (v.catalog as typeof catalog).manifest.files.pop(),
    ],
    [
      "changed external dependencies",
      (v) =>
        (v.catalog as typeof catalog).manifest.external_specifiers.push(
          "synthetic",
        ),
    ],
    ["missing member", (v) => (v.files as unknown[]).pop()],
    [
      "extra member",
      (v) => (v.files as unknown[]).push((v.files as unknown[])[0]),
    ],
    [
      "duplicate member",
      (v) => (v.files as unknown[])[1] = (v.files as unknown[])[0],
    ],
    ["reordered members", (v) => (v.files as unknown[]).reverse()],
    [
      "unsafe path",
      (v) => (v.files as Record<string, unknown>[])[0].path = "../asset",
    ],
    [
      "wrong hash",
      (v) => (v.files as Record<string, unknown>[])[0].sha256 = "0".repeat(64),
    ],
    [
      "wrong byte count",
      (v) => (v.files as Record<string, unknown>[])[0].byte_count = 0,
    ],
    [
      "oversized member",
      (v) =>
        (v.files as Record<string, unknown>[])[0].byte_count =
          INITIAL_ASSET_BYTES + 1,
    ],
    [
      "altered member",
      (v) => (v.files as Record<string, unknown>[])[0].base64 = "AAAA",
    ],
    ["noncanonical base64", (v) => {
      const f = (v.files as Record<string, unknown>[])[0];
      f.base64 = String(f.base64) + "\n";
    }],
    [
      "unknown member field",
      (v) => (v.files as Record<string, unknown>[])[0].extra = 1,
    ],
  ];
  for (const [name, mutate] of mutations) {
    await t.step(name + " rejects before exposure", async () => {
      const value = JSON.parse(baseline);
      mutate(value);
      await assertRejects(() =>
        load(encoder.encode(JSON.stringify(value) + "\n"))
      );
    });
  }
  await t.step(
    "duplicate JSON keys, whitespace, truncation, invalid UTF8 and encoded ceiling reject",
    async () => {
      for (
        const invalid of [
          encoder.encode(
            baseline.replace(
              '"format_version":1',
              '"format_version":1,"format_version":1',
            ),
          ),
          encoder.encode(" " + baseline),
          bytes.subarray(0, bytes.length - 2),
          new Uint8Array([255]),
          new Uint8Array(INITIAL_SOURCE_ARCHIVE_BYTES + 1),
        ]
      ) await assertRejects(() => load(invalid));
    },
  );
  await t.step(
    "missing or altered Git source cannot build; no fallback",
    async () => {
      await assertRejects(() =>
        buildInitialSourceArchiveFromGit(root, signal())
      );
      await assertRejects(() =>
        buildInitialSourceArchive(
          () => Promise.resolve(stream(new Uint8Array([1, 2]))),
          signal(),
        )
      );
    },
  );
  await t.step(
    "cancellation stops a stalled stream and late readers",
    async () => {
      const controller = new AbortController();
      let cancelled = false;
      const pending = resolveInitialSourceArchive(
        new ReadableStream<Uint8Array>({
          cancel() {
            cancelled = true;
          },
        }),
        catalog.digest,
        controller.signal,
      );
      setTimeout(() => controller.abort(), 10);
      await assertRejects(() => pending);
      assert(cancelled);
      let reads = 0;
      await assertRejects(() =>
        buildInitialSourceArchive(() => {
          reads++;
          return Promise.resolve(stream(bytes));
        }, AbortSignal.abort())
      );
      assertEquals(reads, 0);
    },
  );
  await t.step(
    "atomic create, identical retry and concurrent publication",
    async () => {
      const digests = await Promise.all([
        publishInitialSourceArchive(bytes, output, signal()),
        publishInitialSourceArchive(bytes, output, signal()),
      ]);
      assertEquals(digests, [archive.archiveSha256, archive.archiveSha256]);
      assertEquals(
        await Deno.readFile(join(output, `${archive.archiveSha256}.json`)),
        bytes,
      );
    },
  );
  await t.step(
    "interrupted publication preserves complete archive",
    async () => {
      const originalLink = Deno.link;
      Deno.link = () =>
        Promise.reject(new Error("synthetic interrupted publication"));
      try {
        await assertRejects(() =>
          publishInitialSourceArchive(bytes, output, signal())
        );
      } finally {
        Deno.link = originalLink;
      }
      assertEquals(
        await Deno.readFile(join(output, `${archive.archiveSha256}.json`)),
        bytes,
      );
      const names = Array.fromAsync(Deno.readDir(output));
      assertEquals((await names).map((e) => e.name), [
        `${archive.archiveSha256}.json`,
      ]);
    },
  );
  await t.step(
    "corrupt existing content address is never replaced",
    async () => {
      const path = join(output, `${archive.archiveSha256}.json`);
      await Deno.writeTextFile(path, "synthetic corrupt artifact");
      await assertRejects(() =>
        publishInitialSourceArchive(bytes, output, signal())
      );
      assertEquals(await Deno.readTextFile(path), "synthetic corrupt artifact");
      await Deno.remove(path);
      assertEquals(
        (await new Deno.Command("ln", {
          args: ["-s", join(root, "missing"), path],
          stdout: "null",
          stderr: "null",
        }).output()).code,
        0,
      );
      await assertRejects(() =>
        publishInitialSourceArchive(bytes, output, signal())
      );
      assert((await Deno.lstat(path)).isSymlink);
    },
  );
});
