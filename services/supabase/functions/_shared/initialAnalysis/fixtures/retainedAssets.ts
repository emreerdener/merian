import catalog from "../configuration-assets-v1.json" with { type: "json" };
import { resolveInitialSourceArchive } from "../sourceArchive.ts";
import { buildInitialSourceArchiveFromGit } from "../../../../scripts/build_initial_source_archive.ts";
import { repoRoot } from "../../../../scripts/function_dependency_tools.ts";
let archive: ReturnType<typeof resolveInitialSourceArchive> | undefined;
/** Test the retained revision, not mutable working-tree bytes. Production still
 * consumes the bounded immutable archive through its existing resolver. */
export async function retainedInitialTestAsset(
  path: string,
  signal = new AbortController().signal,
) {
  signal.throwIfAborted();
  archive ??= (async () => {
    const deadline = AbortSignal.timeout(60000);
    const bytes = await buildInitialSourceArchiveFromGit(repoRoot, deadline);
    return await resolveInitialSourceArchive(
      new Blob([bytes]).stream(),
      catalog.digest,
      deadline,
    );
  })();
  const resolved = await archive;
  signal.throwIfAborted();
  return await resolved.readAsset(
    path,
    catalog.manifest.repository_revision,
    signal,
  );
}
