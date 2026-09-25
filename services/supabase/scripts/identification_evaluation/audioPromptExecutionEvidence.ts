/** Read-only revalidation of a closed original packet. No dispatch or repair. */
import { join, resolve } from "node:path";
import {
  executionInstant,
  type PromptExecutionRuntime,
  promptExecutionRuntime,
  promptPrivatePreflight,
  readPromptExecution,
  requirePromptControl,
} from "./audioPromptExecution.ts";
import { admitAudioPromptComparisonWindow } from "./audioPromptComparisonWindow.ts";
import { fingerprintBytes, fingerprintJson } from "./evidence.ts";
import { containedPath, exists, readBytes, readJson } from "./files.ts";
import { fields, integer, requireCondition as check } from "./validation.ts";

export const promptSlotId = (slot: number) => String(slot).padStart(2, "0");
export const promptSlotFile = (slot: number, kind: string) =>
  `slots/slot-${promptSlotId(slot)}.${kind}.json`;
export const promptControlFile = (block: number, kind: string) =>
  `controls/block-${block}.${kind}.json`;
export const promptObservationFile = (slot: number) =>
  `observations/slot-${promptSlotId(slot)}.jsonl`;
export const samePromptValue = async (a: unknown, b: unknown) =>
  await fingerprintJson(a) === await fingerprintJson(b);

export async function promptEvidenceFiles(root: string, directory: string) {
  const path = await containedPath(root, directory);
  const stat = await Deno.lstat(path);
  check(stat.isDirectory && stat.mode !== null && (stat.mode & 0o077) === 0);
  const names: string[] = [];
  for await (const entry of Deno.readDir(path)) {
    check(entry.isFile && !entry.isSymlink);
    names.push(entry.name);
  }
  return names.sort();
}

/** Lock an existing inode read-only. Never create or modify original evidence. */
export async function withOriginalPromptLock<T>(
  directory: string,
  work: (root: string) => Promise<T>,
) {
  const root = resolve(directory);
  check(await Deno.realPath(root) === root);
  const path = await containedPath(root, ".lock"),
    before = await Deno.lstat(path);
  check(before.isFile && !before.isSymlink && before.nlink === 1);
  using file = await Deno.open(path, { read: true });
  const opened = await file.stat();
  check(opened.ino === before.ino && opened.dev === before.dev);
  check(await file.tryLock(true));
  try {
    return await work(root);
  } finally {
    await file.unlock();
  }
}

export async function admitBoundPromptObservation(
  bytes: Uint8Array,
  expected: Parameters<typeof admitAudioPromptComparisonWindow>[1],
  pricing: unknown,
  claimedAt: string,
  expiresAt: string,
  now: number,
) {
  check(bytes.length > 0 && bytes.length <= 1_048_576);
  const lines = new TextDecoder("utf-8", { fatal: true }).decode(bytes)
    .trimEnd().split("\n");
  check(lines.length <= 103 && lines.every((line) => line.length <= 16_384));
  const rows = lines.map((line) => JSON.parse(line));
  const admitted = await admitAudioPromptComparisonWindow(rows, expected);
  check(await samePromptValue(rows[0].pricing, pricing));
  const start = executionInstant(rows[0].startedAt),
    finish = executionInstant(rows.at(-1).finishedAt);
  check(start >= executionInstant(claimedAt) && finish <= now);
  check(finish < executionInstant(expiresAt));
  return {
    finishedAt: rows.at(-1).finishedAt as string,
    observationSha256: await fingerprintBytes(bytes),
    admittedSha256: await fingerprintJson(admitted),
    admitted,
  };
}

/** Requires a contiguous completed prefix ending inside a closed block. */
export async function auditOriginalPromptExecution(
  root: string,
  now: number,
  runtime: Pick<PromptExecutionRuntime, "verifyAssets"> =
    promptExecutionRuntime,
) {
  const { manifest, manifestSha256, read } = await readPromptExecution(root);
  await runtime.verifyAssets(root);
  const ledger = await promptEvidenceFiles(root, "slots");
  const completedThrough =
    ledger.filter((name) => name.endsWith(".completed.json")).length;
  integer(completedThrough, 1, 35);
  // A closed partial block also fences the original released ledger, even if
  // somebody invokes that older executable instead of the continuation CLI.
  check(completedThrough % 12 !== 0);
  const slots = Array.from({ length: completedThrough }, (_, i) => i + 1);
  const expectedLedger = slots.flatMap((slot) => [
    `slot-${promptSlotId(slot)}.claim.json`,
    `slot-${promptSlotId(slot)}.completed.json`,
  ]).sort();
  check(await samePromptValue(ledger, expectedLedger));
  check(
    await samePromptValue(
      await promptEvidenceFiles(root, "observations"),
      slots.map((slot) => `slot-${promptSlotId(slot)}.jsonl`),
    ),
  );
  const lastBlock = Math.ceil(completedThrough / 12);
  const blocks = Array.from({ length: lastBlock }, (_, i) => i + 1);
  check(
    await samePromptValue(
      await promptEvidenceFiles(root, "controls"),
      blocks.flatMap((block) => [
        `block-${block}.activation.json`,
        `block-${block}.cleanup.json`,
      ]).sort(),
    ),
  );
  const controls = await Promise.all(blocks.map(async (block) => ({
    block,
    activation: requirePromptControl(
      await read(promptControlFile(block, "activation")),
      manifest,
      block,
      "activation",
    ),
    cleanup: requirePromptControl(
      await read(promptControlFile(block, "cleanup")),
      manifest,
      block,
      "cleanup",
    ),
  })));
  let lastCompletedAt = manifest.preparedAt;
  const rows = [];
  for (const slot of slots) {
    const block = manifest.assignments[slot - 1].block,
      control = controls[block - 1];
    const activationAt = executionInstant(control.activation.observedAt);
    const cleanupAt = executionInstant(control.cleanup.observedAt);
    check(cleanupAt >= activationAt && cleanupAt <= now);
    if (block > 1) {
      check(
        activationAt >=
          executionInstant(controls[block - 2].cleanup.observedAt),
      );
    }
    const claim = fields(await read(promptSlotFile(slot, "claim")), [
      "version",
      "manifestSha256",
      "slot",
      "block",
      "claimedAt",
      "privatePreflight",
      "activationSha256",
      "expected",
    ]);
    const expected = {
      slot,
      app: manifest.review.app,
      backendBundleSha256: manifest.review.backendBundleSha256,
    };
    check(
      claim.version === "audio_prompt_execution_claim_v1" &&
        claim.manifestSha256 === manifestSha256 && claim.slot === slot &&
        claim.block === block,
    );
    check(await samePromptValue(claim.expected, expected));
    check(claim.activationSha256 === await fingerprintJson(control.activation));
    const claimedAt = executionInstant(claim.claimedAt),
      window = manifest.review.windows[block - 1];
    check(
      claimedAt >=
        Math.max(
          activationAt,
          executionInstant(lastCompletedAt),
          executionInstant(window.startsAt),
        ),
    );
    check(claimedAt + 151_000 < executionInstant(window.expiresAt));
    promptPrivatePreflight(
      claim.privatePreflight,
      claimedAt,
      Math.max(activationAt, executionInstant(lastCompletedAt)),
    );
    const done = fields(await read(promptSlotFile(slot, "completed")), [
      "version",
      "manifestSha256",
      "slot",
      "claimSha256",
      "finishedAt",
      "observationSha256",
      "admittedSha256",
      "admitted",
    ]);
    const observation = await admitBoundPromptObservation(
      await readBytes(
        await containedPath(root, promptObservationFile(slot)),
        1_048_576,
      ),
      expected,
      manifest.review.pricing,
      claim.claimedAt as string,
      window.expiresAt,
      now,
    );
    check(
      done.version === "audio_prompt_execution_completion_v1" &&
        done.manifestSha256 === manifestSha256 && done.slot === slot,
    );
    check(done.claimSha256 === await fingerprintJson(claim));
    for (
      const key of [
        "finishedAt",
        "observationSha256",
        "admittedSha256",
        "admitted",
      ] as const
    ) {
      check(await samePromptValue(done[key], observation[key]));
    }
    check(cleanupAt >= executionInstant(observation.finishedAt));
    lastCompletedAt = observation.finishedAt;
    rows.push({ slot, ...observation });
  }
  const paths = [
    "run.json",
    "freeze.json",
    ...ledger.map((n) => "slots/" + n),
    ...slots.map(promptObservationFile),
    ...blocks.flatMap((
      b,
    ) => [promptControlFile(b, "activation"), promptControlFile(b, "cleanup")]),
  ];
  check(
    executionInstant(controls.at(-1)!.cleanup.observedAt) >=
      executionInstant(manifest.review.windows[lastBlock - 1].expiresAt),
  );
  // Optional reviewed UI/witness records are hashed, never interpreted as
  // instructions or emitted. Their presence cannot hide a future attempt.
  for (const directory of ["witnesses", "operator"]) {
    if (!await exists(join(root, directory))) continue;
    for (const name of await promptEvidenceFiles(root, directory)) {
      const match = /^slot-([0-9]{2})(\.preparation-note)?\.json$/.exec(name);
      if (match) integer(Number(match[1]), 1, completedThrough);
      else {check(
          directory === "operator" &&
            (name === "run-interruption.json" ||
              /^block-[1-3]\.preparation-note\.json$/.test(name)),
        );}
      paths.push(directory + "/" + name);
      if (directory === "witnesses") {
        check(match !== null && match[2] === undefined);
        const claim = await read(promptSlotFile(Number(match[1]), "claim")) as {
          privatePreflight: unknown;
        };
        check(
          await samePromptValue(
            await readJson(
              await containedPath(root, directory + "/" + name),
              16_384,
            ),
            claim.privatePreflight,
          ),
        );
      }
    }
  }
  const files = await Promise.all(
    paths.sort().map(async (path) => ({
      path,
      sha256: await fingerprintBytes(
        await readBytes(
          await containedPath(root, path),
          path.startsWith("observations/") ? 1_048_576 : 262_144,
        ),
      ),
    })),
  );
  return {
    binding: {
      manifestSha256,
      evidenceSha256: await fingerprintJson(files),
      completedThrough,
      lastCompletedAt,
      lastCleanupAt: controls.at(-1)!.cleanup.observedAt as string,
      expiredAt: manifest.review.windows[lastBlock - 1].expiresAt,
      app: manifest.review.app,
      backendBundleSha256: manifest.review.backendBundleSha256,
      deployedSha: manifest.review.deployedSha,
      pricing: manifest.review.pricing,
    },
    files,
    rows,
    controls,
  };
}
export type OriginalPromptBinding = Awaited<
  ReturnType<typeof auditOriginalPromptExecution>
>["binding"];
