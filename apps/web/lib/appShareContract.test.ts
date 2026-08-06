import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { CANONICAL_ORIGIN } from "./canonicalHost.ts";

const appShareUrl = new URL(
  "../../ios/Merian/Features/Profile/Shared/AppShareContent.swift",
  import.meta.url,
);
const publicBrandUrl = new URL(
  "../../ios/Shared/Branding/PublicBrand.swift",
  import.meta.url,
);
const homePageUrl = new URL("../app/page.tsx", import.meta.url);
const webQualityWorkflowUrl = new URL(
  "../../../.github/workflows/web-quality.yml",
  import.meta.url,
);

test("prelaunch iOS app sharing targets the served canonical homepage", async () => {
  const [appShare, publicBrand, homePage] = await Promise.all([
    readFile(appShareUrl, "utf8"),
    readFile(publicBrandUrl, "utf8"),
    readFile(homePageUrl, "utf8"),
  ]);

  const websiteMatch = publicBrand.match(
    /websiteURL = URL\(string: "([^"]+)"\)!/,
  );
  assert.ok(websiteMatch, "PublicBrand must define a literal websiteURL.");
  assert.equal(websiteMatch[1], CANONICAL_ORIGIN);

  assert.match(
    appShare,
    /static let destinationURL = PublicBrand\.websiteURL\b/,
  );
  assert.match(appShare, /TODO\(app-store-launch\)/);
  assert.match(
    appShare.replaceAll(/\s+/g, " "),
    /App Store Connect campaign link/,
  );
  assert.doesNotMatch(appShare, /websiteURL\(path:\s*"invite"\)/);
  assert.doesNotMatch(appShare, /naturebook\.earth\/invite/);
  assert.match(homePage, /export default async function HomePage\(\)/);
});

test("web quality runs when the iOS app-share destination changes", async () => {
  const workflow = await readFile(webQualityWorkflowUrl, "utf8");

  for (
    const path of [
      "apps/ios/Merian/Features/Profile/Shared/AppShareContent.swift",
      "apps/ios/Shared/Branding/PublicBrand.swift",
    ]
  ) {
    assert.equal(
      workflow.split(`"${path}"`).length - 1,
      2,
      `${path} must trigger web quality on pull requests and main pushes.`,
    );
  }
});
