import {
  buildAllFunctionGraphs,
  planAffectedFunctions,
} from "./function_dependency_tools.ts";

interface Arguments {
  all: boolean;
  base?: string;
  head?: string;
  changedFiles: string[];
}

function parseArguments(): Arguments {
  const parsed: Arguments = { all: false, changedFiles: [] };
  for (let index = 0; index < Deno.args.length; index += 1) {
    const argument = Deno.args[index];
    if (argument === "--all") {
      parsed.all = true;
    } else if (argument === "--base") {
      parsed.base = Deno.args[++index];
    } else if (argument === "--head") {
      parsed.head = Deno.args[++index];
    } else if (argument === "--changed-file") {
      parsed.changedFiles.push(Deno.args[++index]);
    } else {
      throw new Error(`Unknown or incomplete argument: ${argument}`);
    }
  }
  return parsed;
}

async function changedFilesFromGit(
  base: string,
  head: string,
): Promise<string[] | null> {
  if (!/^[0-9a-f]{40}$/i.test(base) || !/^[0-9a-f]{40}$/i.test(head)) {
    return null;
  }
  const command = new Deno.Command("git", {
    args: ["diff", "--name-only", base, head],
    stdout: "piped",
    stderr: "piped",
  });
  const output = await command.output();
  if (!output.success) return null;
  return new TextDecoder().decode(output.stdout).split("\n").filter(Boolean);
}

async function main(): Promise<void> {
  const args = parseArguments();
  const graphs = await buildAllFunctionGraphs();
  let selected: string[];

  if (args.all) {
    selected = graphs.map((graph) => graph.name).sort();
    console.error("Planning a full Edge Function deployment.");
  } else {
    let changedFiles = args.changedFiles;
    if (changedFiles.length === 0 && args.base && args.head) {
      changedFiles = await changedFilesFromGit(args.base, args.head) ?? [];
      if (changedFiles.length === 0) {
        console.error(
          "Unable to resolve a safe Git diff; falling back to a full deployment.",
        );
        selected = graphs.map((graph) => graph.name).sort();
        for (const name of selected) console.log(name);
        return;
      }
    }
    selected = planAffectedFunctions(changedFiles, graphs);
    console.error(
      `Resolved ${selected.length} affected functions from ${changedFiles.length} changed files.`,
    );
  }

  for (const name of selected) console.log(name);
}

if (import.meta.main) await main();
