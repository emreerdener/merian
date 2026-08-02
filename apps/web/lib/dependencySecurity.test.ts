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
const webQualityWorkflow = readFileSync(
  new URL("../../../.github/workflows/web-quality.yml", import.meta.url),
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

  for (let index = 0; index < Math.max(actual.length, minimum.length); index++) {
    const difference = (actual[index] ?? 0) - (minimum[index] ?? 0);
    if (difference !== 0) {
      return difference > 0;
    }
  }

  return true;
}

test("the lockfile excludes known-vulnerable PostCSS and Sharp releases", () => {
  const postcssVersions = packageVersions("postcss");
  const sharpVersions = packageVersions("sharp");

  assert.ok(postcssVersions.length > 0);
  assert.ok(sharpVersions.length > 0);
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

test("Next transitive security overrides remain explicit", () => {
  assert.deepEqual(packageManifest.overrides?.next, {
    postcss: "8.5.25",
    sharp: "0.35.3",
  });
});

test("web quality runs the blocking dependency audit after frozen install", () => {
  assert.equal(
    packageManifest.scripts?.["audit:dependencies"],
    "npm audit --audit-level=high",
  );

  const installIndex = webQualityWorkflow.indexOf("run: npm ci");
  const auditIndex = webQualityWorkflow.indexOf(
    "run: npm run audit:dependencies",
  );

  assert.ok(installIndex >= 0, "web quality must use npm ci");
  assert.ok(auditIndex > installIndex, "dependency audit must follow npm ci");
});
