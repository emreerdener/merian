import { assert, assertStringIncludes } from "@std/assert";

const sharedDirectory = new URL("../_shared/", import.meta.url);

Deno.test("Gemini runtime requires the paid-project secret without fallback", async () => {
  const gemini = await Deno.readTextFile(new URL("gemini.ts", sharedDirectory));
  const moderation = await Deno.readTextFile(
    new URL("audioModeration.ts", sharedDirectory),
  );
  const workflow = await Deno.readTextFile(
    new URL("../../../../.github/workflows/deploy.yml", import.meta.url),
  );

  for (const source of [gemini, moderation]) {
    assertStringIncludes(source, 'Deno.env.get("GEMINI_PAID_API_KEY")');
    assert(!source.includes('Deno.env.get("GEMINI_API_KEY")'));
  }

  assertStringIncludes(
    workflow,
    "${GEMINI_PAID_API_KEY:?Missing GEMINI_PAID_API_KEY GitHub secret}",
  );
  assertStringIncludes(workflow, "Synchronize paid Gemini API key");
  assertStringIncludes(
    workflow,
    '"GEMINI_PAID_API_KEY=$GEMINI_PAID_API_KEY"',
  );
});
