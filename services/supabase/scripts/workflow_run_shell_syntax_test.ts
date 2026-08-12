import { assert, assertEquals } from "@std/assert";

const workflowsDirectory = new URL(
  "../../../.github/workflows/",
  import.meta.url,
);
const setupDenoActionUrl = new URL(
  "../../../.github/actions/setup-deno/action.yml",
  import.meta.url,
);

interface WorkflowRunScript {
  line: number;
  source: string;
}

function indentation(line: string): number {
  return line.length - line.trimStart().length;
}

function extractRunScripts(workflow: string): WorkflowRunScript[] {
  const lines = workflow.split("\n");
  const scripts: WorkflowRunScript[] = [];

  for (let index = 0; index < lines.length; index++) {
    const match = lines[index].match(/^\s*(?:-\s+)?run:\s*(.*?)\s*$/);
    if (!match) continue;

    const runIndentation = lines[index].indexOf("run:");
    const scalar = match[1];
    if (!scalar) continue; // A defaults.run mapping, not a step script.

    if (!/^[|>][+-]?$/.test(scalar)) {
      scripts.push({ line: index + 1, source: scalar });
      continue;
    }

    const block: string[] = [];
    let contentIndentation: number | null = null;
    let cursor = index + 1;
    for (; cursor < lines.length; cursor++) {
      const line = lines[cursor];
      if (line.trim().length > 0 && indentation(line) <= runIndentation) break;
      if (line.trim().length > 0) {
        contentIndentation = contentIndentation === null
          ? indentation(line)
          : Math.min(contentIndentation, indentation(line));
      }
      block.push(line);
    }

    const prefixLength = contentIndentation ?? runIndentation + 2;
    scripts.push({
      line: index + 1,
      source: block.map((line) =>
        line.trim().length === 0 ? "" : line.slice(prefixLength)
      ).join("\n"),
    });
    index = cursor - 1;
  }

  return scripts;
}

async function bashSyntaxError(script: string): Promise<string | null> {
  const child = new Deno.Command("bash", {
    args: ["--noprofile", "--norc", "-n"],
    stdin: "piped",
    stdout: "null",
    stderr: "piped",
  }).spawn();
  const writer = child.stdin.getWriter();
  await writer.write(new TextEncoder().encode(script));
  await writer.close();
  const output = await child.output();
  return output.success ? null : new TextDecoder().decode(output.stderr).trim();
}

Deno.test("workflow run-script extractor distinguishes defaults from scripts", () => {
  assertEquals(
    extractRunScripts(
      [
        "defaults:",
        "  run:",
        "    working-directory: services",
        "steps:",
        "  - run: echo inline",
        "  - run: |",
        "      if true; then",
        "        echo block",
        "      fi",
      ].join("\n"),
    ),
    [
      { line: 5, source: "echo inline" },
      { line: 6, source: "if true; then\n  echo block\nfi" },
    ],
  );
});

Deno.test("every workflow run script is valid Bash", async () => {
  const violations: string[] = [];
  let scriptCount = 0;

  const validateSource = async (name: string, url: URL) => {
    const source = await Deno.readTextFile(url);
    for (const script of extractRunScripts(source)) {
      scriptCount++;
      const error = await bashSyntaxError(script.source);
      if (error) violations.push(`${name}:${script.line}: ${error}`);
    }
  };

  for await (const entry of Deno.readDir(workflowsDirectory)) {
    if (
      !entry.isFile ||
      (!entry.name.endsWith(".yml") && !entry.name.endsWith(".yaml"))
    ) {
      continue;
    }

    await validateSource(entry.name, new URL(entry.name, workflowsDirectory));
  }
  await validateSource("actions/setup-deno/action.yml", setupDenoActionUrl);

  assert(scriptCount > 0, "No workflow run scripts were discovered.");
  assert(
    violations.length === 0,
    `Invalid workflow Bash:\n${violations.join("\n")}`,
  );
});
