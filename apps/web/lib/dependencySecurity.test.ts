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
  if (!/^\d+\.\d+\.\d+$/.test(version)) return false;
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

test("the lockfile excludes known-vulnerable PostCSS and Sharp releases", () => {
  const postcssVersions = packageVersions("postcss");
  const sharpVersions = packageVersions("sharp");

  assert.ok(postcssVersions.length > 0);
  assert.ok(sharpVersions.length > 0);
  assert.equal(
    postcssVersions.every((version) => versionAtLeast(version, "8.5.25")),
    true,
    `PostCSS versions below 8.5.25: ${postcssVersions.join(", ")}`,
  );
  assert.equal(
    sharpVersions.every((version) => versionAtLeast(version, "0.35.4")),
    true,
    `Sharp versions below 0.35.4: ${sharpVersions.join(", ")}`,
  );
});

test("Next transitive security overrides remain explicit", () => {
  assert.equal(packageManifest.dependencies?.next, "16.3.5");
  assert.deepEqual(packageManifest.overrides?.next, {
    postcss: "8.5.25",
    sharp: "0.35.4",
  });
});

test("the lockfile excludes reviewed Next, Tiptap, and selector parser vulnerabilities", () => {
  for (
    const [name, floor] of [
      ["next", "16.3.5"],
      ["@tiptap/core", "3.30.5"],
      ["postcss-selector-parser", "7.1.3"],
    ]
  ) {
    const versions = packageVersions(name);
    assert.ok(versions.length > 0, `${name} must be present in the lockfile`);
    assert.ok(
      versions.every((version) => versionAtLeast(version, floor)),
      `${name} versions below ${floor}: ${versions.join(", ")}`,
    );
  }
});

test("the Tiptap family shares one patched peer version", () => {
  const version = packageManifest.dependencies?.["@tiptap/pm"];
  assert.equal(version, "3.31.3");
  for (const name of ["extension-link", "react", "starter-kit"]) {
    assert.equal(packageManifest.dependencies?.[`@tiptap/${name}`], version);
  }
  for (const [path, entry] of Object.entries(packageLock.packages ?? {})) {
    if (path.includes("node_modules/@tiptap/")) {
      assert.equal(entry.version, version, `${path} must match Tiptap's peers`);
    }
  }
});

test("the Next build uses the pinned TypeScript compiler API", () => {
  assert.equal(packageManifest.devDependencies?.typescript, "6.0.3");
  assert.deepEqual(packageVersions("typescript"), ["6.0.3"]);
  assert.match(webQualityWorkflow, /run: npm ci --include=dev/);
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
