import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

type LockPackage = {
  version?: string;
};

type PackageLock = {
  packages?: Record<string, LockPackage>;
};

type PackageManifest = {
  dependencies?: Record<string, string>;
  devDependencies?: Record<string, string>;
  scripts?: Record<string, string>;
  overrides?: {
    next?: Record<string, string>;
  };
};

const packageManifest = JSON.parse(
  readFileSync(new URL("../package.json", import.meta.url), "utf8"),
) as PackageManifest;
const packageLock = JSON.parse(
  readFileSync(new URL("../package-lock.json", import.meta.url), "utf8"),
) as PackageLock;
const adminQualityWorkflow = readFileSync(
  new URL(
    "../../../.github/workflows/admin-quality.yml",
    import.meta.url,
  ),
  "utf8",
);

function packageVersions(packageName: string): string[] {
  return Object.entries(packageLock.packages ?? {})
    .filter(
      ([path]) =>
        path === `node_modules/${packageName}` ||
        path.endsWith(`/node_modules/${packageName}`),
    )
    .map(([, entry]) => entry.version)
    .filter((version): version is string => version !== undefined);
}

function versionAtLeast(version: string, floor: string): boolean {
  const actual = version.split(".").map(Number);
  const minimum = floor.split(".").map(Number);

  for (
    let index = 0;
    index < Math.max(actual.length, minimum.length);
    index++
  ) {
    const difference = (actual[index] ?? 0) - (minimum[index] ?? 0);
    if (difference !== 0) {
      return difference > 0;
    }
  }

  return true;
}

test("the frozen admin graph excludes reviewed vulnerable dependency ranges", () => {
  const nextVersions = packageVersions("next");
  const postcssVersions = packageVersions("postcss");
  const sharpVersions = packageVersions("sharp");

  assert.ok(nextVersions.length > 0, "Next.js must be present in the lockfile");
  assert.ok(
    postcssVersions.length > 0,
    "PostCSS must be present in the lockfile",
  );
  assert.ok(sharpVersions.length > 0, "Sharp must be present in the lockfile");

  assert.equal(
    nextVersions.every((version) => versionAtLeast(version, "16.2.12")),
    true,
    `Next.js versions below 16.2.12: ${nextVersions.join(", ")}`,
  );
  assert.equal(
    postcssVersions.every((version) => versionAtLeast(version, "8.5.18")),
    true,
    `PostCSS versions below 8.5.18: ${postcssVersions.join(", ")}`,
  );
  assert.equal(
    sharpVersions.every((version) => versionAtLeast(version, "0.35.0")),
    true,
    `Sharp versions below 0.35.0: ${sharpVersions.join(", ")}`,
  );
});

test("Next.js transitive security overrides remain explicit", () => {
  assert.equal(packageManifest.dependencies?.next, "16.2.12");
  assert.equal(packageManifest.devDependencies?.postcss, "8.5.18");
  assert.deepEqual(packageManifest.overrides?.next, {
    postcss: "8.5.18",
    sharp: "0.35.3",
  });
});

test("admin quality gates the frozen graph before test, type-check, and build", () => {
  assert.equal(
    packageManifest.scripts?.["audit:dependencies"],
    "npm audit --audit-level=high",
  );
  const pullRequestIndex = adminQualityWorkflow.indexOf("  pull_request:");
  const pushIndex = adminQualityWorkflow.indexOf("  push:");
  const dispatchIndex = adminQualityWorkflow.indexOf("  workflow_dispatch:");
  assert.ok(pullRequestIndex >= 0, "pull_request trigger is missing");
  assert.ok(pushIndex > pullRequestIndex, "push trigger is missing");
  assert.ok(dispatchIndex > pushIndex, "workflow_dispatch trigger is missing");

  const pullRequestBlock = adminQualityWorkflow.slice(
    pullRequestIndex,
    pushIndex,
  );
  const pushBlock = adminQualityWorkflow.slice(pushIndex, dispatchIndex);
  assert.doesNotMatch(
    pullRequestBlock,
    /\bpaths:/,
    "The required pull-request check must report for every pull request",
  );
  assert.match(pushBlock, /- "apps\/admin\/\*\*"/);

  const commands = [
    "run: npm ci",
    "run: npm run audit:dependencies",
    "run: npm test",
    "run: npm run typecheck",
    "run: npm run build",
  ];
  let previousIndex = -1;
  for (const command of commands) {
    const index = adminQualityWorkflow.indexOf(command);
    assert.ok(index > previousIndex, `${command} is missing or out of order`);
    previousIndex = index;
  }
});
