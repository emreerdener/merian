import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const termsUrl = new URL("../app/terms/page.tsx", import.meta.url);
const privacyUrl = new URL("../app/privacy/page.tsx", import.meta.url);
const choicesUrl = new URL("../app/privacy-choices/page.tsx", import.meta.url);
const deleteSheetUrl = new URL(
  "../../ios/Merian/Features/Profile/Settings/Views/DeleteAccountSheet.swift",
  import.meta.url,
);
const locationStepUrl = new URL(
  "../../ios/Merian/Features/Onboarding/Steps/LocationPermission/LocationPermissionStepView.swift",
  import.meta.url,
);
const infoPlistUrl = new URL(
  "../../ios/Merian/Configuration/Info.plist",
  import.meta.url,
);
const webQualityWorkflowUrl = new URL(
  "../../../.github/workflows/web-quality.yml",
  import.meta.url,
);

test("legal and iOS surfaces share the mandatory scientific-retention contract", async () => {
  const sources = await Promise.all([
    readFile(termsUrl, "utf8"),
    readFile(privacyUrl, "utf8"),
    readFile(choicesUrl, "utf8"),
    readFile(deleteSheetUrl, "utf8"),
    readFile(locationStepUrl, "utf8"),
    readFile(infoPlistUrl, "utf8"),
  ]);
  const [terms, privacy, choices, deleteSheet, locationStep, infoPlist] =
    sources.map((source) => source.replaceAll(/\s+/g, " "));

  for (
    const fragment of [
      "Every scan submitted to Naturebook contributes a scientific",
      "required, non-optional condition",
      "exact and privacy-projected coordinates when",
      "Account deletion does not delete Scientific Data",
    ]
  ) {
    assert.ok(terms.includes(fragment), `Terms are missing: ${fragment}`);
  }

  for (
    const fragment of [
      "required backend scientific observation record",
      "do not have a separate opt-in or opt-out control",
      "retained for the life of the Naturebook scientific observation",
      "keeps exact coordinates",
    ]
  ) {
    assert.ok(
      privacy.includes(fragment),
      `Privacy Policy is missing: ${fragment}`,
    );
  }

  for (
    const fragment of [
      "Every submitted scan contributes a scientific observation",
      "There is no separate opt-in or opt-out control",
      "does not delete this ownerless scientific record",
    ]
  ) {
    assert.ok(
      choices.includes(fragment),
      `Privacy Choices is missing: ${fragment}`,
    );
  }

  assert.ok(
    deleteSheet.includes(
      "Scientific observations you submitted—including exact coordinates, time, and taxonomy—will remain without account attribution.",
    ),
  );
  assert.ok(
    !deleteSheet.includes("All uploaded scans and cloud backups will perish."),
  );
  assert.ok(!deleteSheet.includes("hard wipe of your account"));

  assert.ok(
    locationStep.includes(
      "becomes part of each submitted scientific observation",
    ),
  );
  assert.ok(
    locationStep.includes(
      "exact coordinates remain in Naturebook's scientific backend record",
    ),
  );
  assert.ok(!locationStep.includes("always remain strictly private"));

  assert.ok(
    infoPlist.includes(
      "the scientific observation record created when you submit a scan",
    ),
  );
});

test("web quality runs when an iOS retention-disclosure surface changes", async () => {
  const workflow = await readFile(webQualityWorkflowUrl, "utf8");

  for (
    const path of [
      "apps/ios/Merian/Configuration/Info.plist",
      "apps/ios/Merian/Features/Onboarding/Steps/LocationPermission/LocationPermissionStepView.swift",
      "apps/ios/Merian/Features/Profile/Settings/Views/DeleteAccountSheet.swift",
    ]
  ) {
    assert.equal(
      workflow.split(`\"${path}\"`).length - 1,
      2,
      `${path} must trigger web quality on pull requests and main pushes.`,
    );
  }
});
