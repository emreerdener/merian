type ManifestCase = {
  id: string;
  suite: string;
  prompt: string;
  expectedActions: string[];
  requiredSafetyFlags: string[];
};

function argument(name: string): string {
  const index = Deno.args.indexOf(name);
  if (index < 0 || !Deno.args[index + 1]) throw new Error(`missing ${name}`);
  return Deno.args[index + 1];
}

if (import.meta.main) {
  const manifestPath = argument("--manifest");
  const outputPath = argument("--output");
  const suite = argument("--suite");
  const manifest = JSON.parse(await Deno.readTextFile(manifestPath)) as {
    cases: ManifestCase[];
  };
  const selected = manifest.cases.filter((testCase) =>
    suite === "all" || testCase.suite === suite
  );
  if (!selected.length) throw new Error(`suite ${suite} has no cases`);
  const input = {
    schemaVersion: 1,
    suite,
    skillCatalog: [
      "merian-api-contracts",
      "merian-ios",
      "merian-release",
      "merian-supabase",
      "merian-swiftdata-migrations",
      "merian-web-admin",
    ],
    agentCatalog: [
      "merian_contract_auditor",
      "merian_explorer",
      "merian_reviewer",
    ],
    actionCatalog: [
      ...new Set(selected.flatMap((testCase) => testCase.expectedActions)),
    ].sort(),
    safetyFlagCatalog: [
      ...new Set(selected.flatMap((testCase) => testCase.requiredSafetyFlags)),
    ].sort(),
    cases: selected.map(({ id, prompt }) => ({ id, prompt })),
  };
  await Deno.writeTextFile(outputPath, `${JSON.stringify(input, null, 2)}\n`);
}
