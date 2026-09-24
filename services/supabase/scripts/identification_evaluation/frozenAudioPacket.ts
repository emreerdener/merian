/** Narrow reader for previously reviewed private audio packets. No live I/O. */
import { resolve } from "node:path";
import { assertOfflinePermissions } from "./admission.ts";
import { prepareAudioPromptPair } from "./audioPromptComparison.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import { parseExploratoryCorpus, referenceLabels } from "./exploratory.ts";
import { containedPath, readBytes } from "./files.ts";
import { hash, parseTaxonomy, referenceTaxaExist } from "./runContracts.ts";
import {
  array,
  fields,
  integer,
  requireCondition as check,
} from "./validation.ts";

export interface FrozenAudioSourceBinding {
  completedFreezeSha256: string;
  sourceCorpusSha256: string;
  sourceTaxonomySha256: string;
}
export interface FrozenAudioCaseBinding {
  caseId: string;
  groupId: string;
  assetPath: string;
  sourceWavSha256: string;
  byteLength: number;
  provisionalReference: unknown;
}
const json = (bytes: Uint8Array): unknown =>
  JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));

/** The caller supplies a reviewed expected freeze, never a hash read from the
 * packet itself. The public CLI fixes all bindings to the checked-in design.
 * Historical outcomes/prose are neither read nor treated as reference truth.
 */
export async function readFrozenAudioPacket(
  source: string,
  binding: FrozenAudioSourceBinding,
  selected: readonly FrozenAudioCaseBinding[],
  now: number,
) {
  await assertOfflinePermissions();
  const root = resolve(source);
  const rootStat = await Deno.lstat(root);
  check(
    rootStat.isDirectory && !rootStat.isSymlink &&
      rootStat.mode !== null && (rootStat.mode & 0o077) === 0,
  );
  check(await Deno.realPath(root) === root);
  const privateRead = async (path: string, limit: number) => {
    const target = await containedPath(root, path);
    const stat = await Deno.lstat(target);
    check(stat.mode !== null && (stat.mode & 0o077) === 0);
    return await readBytes(target, limit);
  };
  const freezeBytes = await privateRead("completed-freeze.json", 1024 * 1024);
  check(await fingerprintBytes(freezeBytes) === binding.completedFreezeSha256);
  const freeze = fields(json(freezeBytes), [
    "createdAt",
    "retentionThrough",
    "files",
  ]);
  check(
    typeof freeze.createdAt === "string" &&
      Number.isFinite(now) && Date.parse(freeze.createdAt) <= now,
  );
  const files = array(freeze.files, 1, 512).map((raw) => {
    const file = fields(raw, ["path", "sha256", "byteLength"]);
    check(typeof file.path === "string");
    hash(file.sha256);
    integer(file.byteLength, 1, 8 * 1024 * 1024);
    return {
      path: file.path,
      sha256: file.sha256,
      byteLength: file.byteLength,
    };
  });
  check(new Set(files.map((file) => file.path)).size === files.length);
  const frozenRead = async (path: string, limit: number) => {
    const file = files.find((f) => f.path === path);
    check(file);
    const bytes = await privateRead(path, limit);
    check(
      bytes.length === file.byteLength &&
        await fingerprintBytes(bytes) === file.sha256,
    );
    return bytes;
  };
  const corpusBytes = await frozenRead("corpus.json", 1024 * 1024);
  const taxonomyBytes = await frozenRead("taxonomy.json", 1024 * 1024);
  check(await fingerprintBytes(corpusBytes) === binding.sourceCorpusSha256);
  check(await fingerprintBytes(taxonomyBytes) === binding.sourceTaxonomySha256);
  const corpus = parseExploratoryCorpus(json(corpusBytes));
  const taxonomy = parseTaxonomy(json(taxonomyBytes));
  const eligibility = corpus.eligibility;
  check(
    corpus.evidenceOrigin === "real" && eligibility &&
      eligibility.reviewerKind === "owner" &&
      eligibility.retainUntil === freeze.retentionThrough &&
      Date.parse(eligibility.retainUntil) > now,
  );
  check(
    corpus.taxonomyVersion === taxonomy.taxonomyVersion &&
      referenceTaxaExist(
        taxonomy,
        referenceLabels(corpus).flatMap((r) => [...r.acceptableTaxa]),
      ),
  );
  const recordHash = async (ref: string) =>
    await fingerprintBytes(
      await frozenRead("records/" + ref + ".json", 1024 * 1024),
    );
  const eligibilitySha256 = await recordHash(eligibility.recordRef);
  check(
    selected.length > 0 && selected.length <= 6 &&
      new Set(selected.map((c) => c.caseId)).size === selected.length,
  );
  const cases = [];
  for (const expected of selected) {
    const entry = corpus.cases.find((c) => c.input.caseId === expected.caseId);
    check(entry);
    const { input, curation } = entry;
    check(
      input.groupId === expected.groupId && input.inputGroup === "audio" &&
        input.observationTexts.length === 0 && input.clips.length === 0 &&
        input.context.deviceRegion === null &&
        input.context.currentMonth === null &&
        input.assets.length === 1,
    );
    const asset = input.assets[0];
    check(
      asset.kind === "audio" && asset.sourceIndex === 0 &&
        asset.path === expected.assetPath &&
        asset.sha256 === expected.sourceWavSha256 &&
        asset.byteLength === expected.byteLength,
    );
    check(
      await fingerprintJson(entry.provisionalReference) ===
        await fingerprintJson(expected.provisionalReference),
    );
    check(
      curation.kind === "eligibility_reviewed" && curation.referenceRecordRef,
    );
    const sourceRecordSha256 = await recordHash(curation.sourceRecordRef);
    const referenceRecordSha256 = await recordHash(curation.referenceRecordRef);
    const bytes = await frozenRead(asset.path, 44 + 44100 * 15 * 2);
    check(
      await fingerprintBytes(bytes) === expected.sourceWavSha256 &&
        bytes.length === expected.byteLength,
    );
    cases.push({
      caseId: input.caseId,
      groupId: input.groupId,
      assetPath: asset.path,
      sourceRecordSha256,
      referenceRecordSha256,
      referenceSha256: await fingerprintJson(entry.provisionalReference),
      ...await prepareAudioPromptPair(bytes),
    });
  }
  return {
    source: {
      ...binding,
      eligibilitySha256,
      retainUntil: eligibility.retainUntil,
      permission: "gemini_evaluation" as const,
      reviewerKind: "owner" as const,
    },
    cases,
  };
}
