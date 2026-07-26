/**
 * Identify Edge wire-contract validator and Swift DTO generator.
 *
 * The deployed runtime, provider schema, and generated Swift decoding boundary
 * all consume the executable contract in _shared/identify/contract.ts. This
 * gate verifies the checked-in generated Swift block and its exclusive
 * ownership across the complete apps/ios source graph.
 */

import { dirname, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import {
  type ContractField,
  type ContractNode,
  identifyWireEnvelopeContract,
  merianDescribeModelContract,
  merianModelContract,
  type ObjectContract,
  providerSchemaFromContract,
} from "../functions/_shared/identify/contract.ts";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = resolve(scriptDirectory, "../../..");

export const canonicalContractPath = resolve(
  repositoryRoot,
  "services/supabase/functions/_shared/identify/contract.ts",
);
export const canonicalSwiftDTOPath = resolve(
  repositoryRoot,
  "apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift",
);
export const iosSourceGraphRoot = resolve(repositoryRoot, "apps/ios");

export const REQUIRED_IOS_PRODUCTION_SOURCE_ROOTS = [
  "apps/ios/Merian",
  "apps/ios/Shared/Branding",
  "apps/ios/messages/ScanSharing/AppSupport",
  "apps/ios/messages/ScanSharing/Shared",
] as const;

export const GENERATED_SWIFT_BEGIN = "// BEGIN GENERATED: Identify wire DTOs";
export const GENERATED_SWIFT_END = "// END GENERATED: Identify wire DTOs";

export const REQUIRED_MODEL_PATHS = [
  "ai_reasoning",
  "candidates[].confidence_score",
  "candidates[].scientific_name",
  "confidence_score",
  "ecological_interactions[]",
  "image_quality.overall_score",
  "individual_count",
  "is_biological_subject",
  "is_live_capture",
  "pet_identification.confidence_score",
] as const;

export const REQUIRED_WIRE_PATHS = [
  "data.candidates[].common_name",
  "data.confidence_score",
  "data.estimated_size_cm",
  "data.gbif_taxon_key",
  "data.group_tags[]",
  "data.image_quality.overall_score",
  "data.inference_tier",
  "data.insight_data.ai_reasoning",
  "data.pet_identification.label_type",
  "data.scan_id",
  "data.species_insights.habitat_description",
  "data.taxonomy.class",
  "success",
] as const;

export class ContractValidationError extends Error {
  override readonly name = "ContractValidationError";
}

export interface ContractPathReport {
  readonly paths: ReadonlySet<string>;
  readonly numericPaths: ReadonlySet<string>;
  readonly ignoredSwiftPaths: ReadonlySet<string>;
}

export interface SwiftSourceEntry {
  readonly path: string;
  readonly source: string;
}

export interface ContractValidationReport {
  readonly generatedStructNames: readonly string[];
  readonly modelPathCount: number;
  readonly wirePathCount: number;
  readonly numericPathCount: number;
  readonly ignoredSwiftPaths: readonly string[];
  readonly swiftSourceCount: number;
  readonly productionSourceRootCounts: Readonly<Record<string, number>>;
}

function pathForChild(path: string, child: string): string {
  return path ? `${path}.${child}` : child;
}

export function collectContractPaths(
  root: ContractNode,
): ContractPathReport {
  const paths = new Set<string>();
  const numericPaths = new Set<string>();
  const ignoredSwiftPaths = new Set<string>();
  const active = new Set<ContractNode>();

  const visit = (
    node: ContractNode,
    path: string,
    swiftField?: ContractField,
  ): void => {
    if (path) paths.add(path);
    if (swiftField?.swift === false && path) ignoredSwiftPaths.add(path);
    if (node.kind === "integer" || node.kind === "number") {
      numericPaths.add(path);
    }
    if (active.has(node)) {
      throw new ContractValidationError(
        `Recursive contract node at '${path || "<root>"}' is unsupported.`,
      );
    }
    if (node.kind === "array") {
      active.add(node);
      visit(node.items, `${path}[]`);
      active.delete(node);
    } else if (node.kind === "object") {
      active.add(node);
      for (const [name, definition] of Object.entries(node.fields)) {
        visit(
          definition.contract,
          pathForChild(path, name),
          definition,
        );
      }
      active.delete(node);
    }
  };

  visit(root, "");
  return { paths, numericPaths, ignoredSwiftPaths };
}

function assertFiniteNumericContracts(
  root: ContractNode,
  contractName: string,
): void {
  const visited = new Set<ContractNode>();
  const visit = (node: ContractNode, path: string): void => {
    if (visited.has(node)) return;
    visited.add(node);
    if (node.kind === "integer" || node.kind === "number") {
      if (
        !Number.isFinite(node.minimum) || !Number.isFinite(node.maximum) ||
        node.minimum > node.maximum
      ) {
        throw new ContractValidationError(
          `${contractName} numeric '${path}' must have ordered finite bounds.`,
        );
      }
      if (
        node.kind === "integer" &&
        (!Number.isSafeInteger(node.minimum) ||
          !Number.isSafeInteger(node.maximum))
      ) {
        throw new ContractValidationError(
          `${contractName} integer '${path}' must use JavaScript-safe bounds.`,
        );
      }
    } else if (node.kind === "array") {
      visit(node.items, `${path}[]`);
    } else if (node.kind === "object") {
      for (const [name, definition] of Object.entries(node.fields)) {
        visit(definition.contract, pathForChild(path, name));
      }
    }
  };
  visit(root, "");
}

function assertRequiredPaths(
  report: ContractPathReport,
  required: readonly string[],
  contractName: string,
): void {
  const missing = required.filter((path) => !report.paths.has(path));
  if (missing.length > 0) {
    throw new ContractValidationError(
      `${contractName} is missing required path(s): ${missing.join(", ")}.`,
    );
  }
}

function collectSwiftObjects(
  root: ContractNode,
): ReadonlyMap<string, ObjectContract> {
  const objects = new Map<string, ObjectContract>();
  const visited = new Set<ContractNode>();
  const visit = (node: ContractNode, path: string): void => {
    if (visited.has(node)) return;
    visited.add(node);
    if (node.kind === "array") {
      visit(node.items, `${path}[]`);
      return;
    }
    if (node.kind !== "object") return;
    if (node.swift) {
      const previous = objects.get(node.swift.name);
      if (previous && previous !== node) {
        throw new ContractValidationError(
          `Swift DTO name '${node.swift.name}' is assigned to multiple contract objects.`,
        );
      }
      objects.set(node.swift.name, node);
    }
    for (const [name, definition] of Object.entries(node.fields)) {
      if (definition.swift === false) continue;
      const child = definition.contract;
      const unwrapped = child.kind === "array" ? child.items : child;
      if (unwrapped.kind === "object" && !unwrapped.swift) {
        throw new ContractValidationError(
          `Swift-visible object '${
            pathForChild(path, name)
          }' has no generated DTO metadata.`,
        );
      }
      visit(child, pathForChild(path, name));
    }
  };
  visit(root, "");
  return objects;
}

function swiftIdentifier(jsonName: string, definition: ContractField): string {
  return definition.swift && definition.swift.name
    ? definition.swift.name
    : jsonName;
}

function bareSwiftIdentifier(identifier: string): string {
  return identifier.startsWith("`") && identifier.endsWith("`")
    ? identifier.slice(1, -1)
    : identifier;
}

function swiftBaseType(contract: ContractNode): string {
  switch (contract.kind) {
    case "boolean":
      return "Bool";
    case "integer":
      return "Int";
    case "number":
      return "Double";
    case "string":
      return "String";
    case "array": {
      const itemType = swiftBaseType(contract.items);
      return `[${contract.items.nullable ? `${itemType}?` : itemType}]`;
    }
    case "object":
      if (!contract.swift) {
        throw new ContractValidationError(
          "A Swift-visible object is missing Swift type metadata.",
        );
      }
      return contract.swift.name;
  }
}

function isSwiftPropertyOptional(
  owner: ObjectContract,
  definition: ContractField,
): boolean {
  if (definition.swift && definition.swift.optional !== undefined) {
    return definition.swift.optional;
  }
  if (owner.swift?.defaultPropertyOptional) return true;
  return !definition.required || definition.contract.nullable === true;
}

function swiftPropertyType(
  owner: ObjectContract,
  definition: ContractField,
): string {
  const base = swiftBaseType(definition.contract);
  return isSwiftPropertyOptional(owner, definition) ? `${base}?` : base;
}

function indentation(level: number): string {
  return "    ".repeat(level);
}

function renderSwiftStruct(
  node: ObjectContract,
  allObjects: ReadonlyMap<string, ObjectContract>,
  level: number,
): string {
  if (!node.swift) {
    throw new ContractValidationError(
      "Cannot render an object without Swift metadata.",
    );
  }
  const indent = indentation(level);
  const childIndent = indentation(level + 1);
  const lines: string[] = [
    `${indent}struct ${node.swift.name}: Codable {`,
  ];

  const nested = [...allObjects.values()]
    .filter((candidate) => candidate.swift?.parent === node.swift?.name)
    .sort((left, right) =>
      (left.swift?.declarationOrder ?? 0) -
      (right.swift?.declarationOrder ?? 0)
    );
  for (const child of nested) {
    lines.push(renderSwiftStruct(child, allObjects, level + 1), "");
  }

  const properties = Object.entries(node.fields)
    .filter(([, definition]) => definition.swift !== false);
  for (const [jsonName, definition] of properties) {
    lines.push(
      `${childIndent}let ${swiftIdentifier(jsonName, definition)}: ${
        swiftPropertyType(node, definition)
      }`,
    );
  }

  lines.push("", `${childIndent}enum CodingKeys: String, CodingKey {`);
  for (const [jsonName, definition] of properties) {
    const identifier = swiftIdentifier(jsonName, definition);
    const bare = bareSwiftIdentifier(identifier);
    lines.push(
      bare === jsonName
        ? `${indentation(level + 2)}case ${identifier}`
        : `${indentation(level + 2)}case ${identifier} = "${jsonName}"`,
    );
  }
  lines.push(`${childIndent}}`, "");

  lines.push(
    `${childIndent}init(from decoder: Decoder) throws {`,
    `${
      indentation(level + 2)
    }let container = try decoder.container(keyedBy: CodingKeys.self)`,
  );
  for (const [jsonName, definition] of properties) {
    const identifier = swiftIdentifier(jsonName, definition);
    const baseType = swiftBaseType(definition.contract);
    const decodeMethod = isSwiftPropertyOptional(node, definition)
      ? "decodeIfPresent"
      : "decode";
    lines.push(
      `${
        indentation(level + 2)
      }${identifier} = try container.${decodeMethod}(${baseType}.self, forKey: .${identifier})`,
    );
  }
  lines.push(`${childIndent}}`, `${indent}}`);
  return lines.join("\n");
}

export function renderGeneratedSwiftDTOBlock(): string {
  const objects = collectSwiftObjects(identifyWireEnvelopeContract);
  const topLevel = [...objects.values()]
    .filter((node) => !node.swift?.parent)
    .sort((left, right) =>
      (left.swift?.declarationOrder ?? 0) -
      (right.swift?.declarationOrder ?? 0)
    );
  return [
    GENERATED_SWIFT_BEGIN,
    "// Generated from services/supabase/functions/_shared/identify/contract.ts.",
    "// Do not edit this block by hand; run make generate-edge-dto-contract.",
    "",
    ...topLevel.flatMap((node, index) => [
      ...(index > 0 ? [""] : []),
      renderSwiftStruct(node, objects, 0),
    ]),
    GENERATED_SWIFT_END,
  ].join("\n");
}

export function validateGeneratedSwiftSource(source: string): void {
  const expected = renderGeneratedSwiftDTOBlock();
  const begin = source.indexOf(GENERATED_SWIFT_BEGIN);
  const endMarker = source.indexOf(GENERATED_SWIFT_END);
  if (begin < 0 || endMarker < 0 || endMarker < begin) {
    throw new ContractValidationError(
      "InferenceEdgeDTOs.swift is missing the generated Identify DTO markers.",
    );
  }
  if (
    source.indexOf(GENERATED_SWIFT_BEGIN, begin + 1) >= 0 ||
    source.indexOf(GENERATED_SWIFT_END, endMarker + 1) >= 0
  ) {
    throw new ContractValidationError(
      "InferenceEdgeDTOs.swift contains duplicate generated DTO markers.",
    );
  }
  const end = endMarker + GENERATED_SWIFT_END.length;
  const actual = source.slice(begin, end).replaceAll("\r\n", "\n");
  if (actual !== expected) {
    throw new ContractValidationError(
      "Generated Identify Swift DTOs are stale. Regenerate the marked block from the executable contract.",
    );
  }
}

export function replaceGeneratedSwiftDTOBlock(source: string): string {
  const begin = source.indexOf(GENERATED_SWIFT_BEGIN);
  const endMarker = source.indexOf(GENERATED_SWIFT_END);
  if (begin < 0 || endMarker < 0 || endMarker < begin) {
    throw new ContractValidationError(
      "InferenceEdgeDTOs.swift is missing the generated Identify DTO markers.",
    );
  }
  if (
    source.indexOf(GENERATED_SWIFT_BEGIN, begin + 1) >= 0 ||
    source.indexOf(GENERATED_SWIFT_END, endMarker + 1) >= 0
  ) {
    throw new ContractValidationError(
      "InferenceEdgeDTOs.swift contains duplicate generated DTO markers.",
    );
  }
  const end = endMarker + GENERATED_SWIFT_END.length;
  return `${source.slice(0, begin)}${renderGeneratedSwiftDTOBlock()}${
    source.slice(end)
  }`;
}

function sourceOutsideGeneratedSwiftDTOBlock(source: string): string {
  const begin = source.indexOf(GENERATED_SWIFT_BEGIN);
  const endMarker = source.indexOf(GENERATED_SWIFT_END);
  if (begin < 0 || endMarker < 0 || endMarker < begin) return source;
  const end = endMarker + GENERATED_SWIFT_END.length;
  return `${source.slice(0, begin)}\n${source.slice(end)}`;
}

function escapeRegularExpression(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function directGeneratedTarget(
  target: string,
  aliases: ReadonlyMap<string, ReadonlySet<string>>,
  generatedQualifiedNames: ReadonlySet<string>,
  generatedTopLevelNames: ReadonlySet<string>,
): string | undefined {
  const canonicalGeneratedName = (candidate: string): string | undefined => {
    for (const name of generatedQualifiedNames) {
      if (candidate === name || candidate.endsWith(`.${name}`)) return name;
    }
    for (const name of generatedTopLevelNames) {
      if (candidate === name || candidate.endsWith(`.${name}`)) return name;
    }
    return undefined;
  };

  const visited = new Set<string>();
  const pending = [target];
  while (pending.length > 0) {
    const current = pending.shift()!;
    if (visited.has(current)) continue;
    visited.add(current);

    const generatedName = canonicalGeneratedName(current);
    if (generatedName) return generatedName;

    const aliasName = current.split(".").at(-1) ?? current;
    for (const next of aliases.get(aliasName) ?? []) {
      if (!visited.has(next)) pending.push(next);
    }
  }
  return undefined;
}

/**
 * Generated DTOs own their CodingKeys and init(from:) implementations. Any
 * additional extension of those DTOs is prohibited. An attempted decoder
 * override that evades this fast source-policy diagnostic is still an invalid
 * Swift redeclaration and cannot compile.
 */
export function validateSwiftSourceOwnership(
  entries: readonly SwiftSourceEntry[],
  canonicalPath = canonicalSwiftDTOPath,
): void {
  const generatedObjects = collectSwiftObjects(identifyWireEnvelopeContract);
  const generatedTopLevelNames = new Set(
    [...generatedObjects.values()]
      .filter((node) => !node.swift?.parent)
      .map((node) => node.swift?.name)
      .filter((name): name is string => name !== undefined),
  );
  const generatedQualifiedNames = new Set(
    [...generatedObjects.values()]
      .map((node) =>
        node.swift?.parent
          ? `${node.swift.parent}.${node.swift.name}`
          : node.swift?.name
      )
      .filter((name): name is string => name !== undefined),
  );
  const searchableEntries = entries.map((entry) => ({
    ...entry,
    source: resolve(entry.path) === resolve(canonicalPath)
      ? sourceOutsideGeneratedSwiftDTOBlock(entry.source)
      : entry.source,
  }));
  // Swift aliases have module scope even when declarations and extensions live
  // in different files. Retain every observed binding instead of allowing a
  // later same-name decoy to overwrite the generated target.
  const aliases = new Map<string, Set<string>>();
  const aliasPattern =
    /^\s*(?:(?:public|internal|private|fileprivate)\s+)?typealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([A-Za-z_][A-Za-z0-9_.]*)/gm;
  for (const entry of searchableEntries) {
    for (const match of entry.source.matchAll(aliasPattern)) {
      const targets = aliases.get(match[1]) ?? new Set<string>();
      targets.add(match[2]);
      aliases.set(match[1], targets);
    }
  }

  const failures: string[] = [];
  for (const entry of searchableEntries) {
    const source = entry.source;
    for (const name of generatedTopLevelNames) {
      const declaration = new RegExp(
        `^\\s*(?:(?:public|internal|private|fileprivate|open|final|indirect)\\s+)*(?:struct|class|enum|actor|typealias)\\s+${
          escapeRegularExpression(name)
        }\\b`,
        "m",
      );
      if (declaration.test(source)) {
        failures.push(`${entry.path}: redeclares generated DTO '${name}'`);
      }
    }

    const extensionPattern = /\bextension\s+([A-Za-z_][A-Za-z0-9_.]*)\b/g;
    for (const match of source.matchAll(extensionPattern)) {
      const generated = directGeneratedTarget(
        match[1],
        aliases,
        generatedQualifiedNames,
        generatedTopLevelNames,
      );
      if (generated) {
        failures.push(
          `${entry.path}: extends generated DTO '${generated}'; put protocol changes in the executable contract`,
        );
      }
    }
  }
  if (failures.length > 0) {
    throw new ContractValidationError(
      `Generated Swift DTO ownership validation failed:\n${
        failures.map((failure) => `- ${failure}`).join("\n")
      }`,
    );
  }
}

export async function discoverSwiftSourcePaths(
  root: string,
): Promise<string[]> {
  const paths: string[] = [];
  const visit = async (directory: string): Promise<void> => {
    const entries: Deno.DirEntry[] = [];
    for await (const entry of Deno.readDir(directory)) entries.push(entry);
    entries.sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const path = join(directory, entry.name);
      if (entry.isDirectory) {
        await visit(path);
      } else if (entry.isFile && entry.name.endsWith(".swift")) {
        paths.push(path);
      }
    }
  };
  await visit(root);
  return paths;
}

function productionRootCounts(
  swiftPaths: readonly string[],
): Readonly<Record<string, number>> {
  const counts: Record<string, number> = {};
  for (const localRoot of REQUIRED_IOS_PRODUCTION_SOURCE_ROOTS) {
    const absoluteRoot = resolve(repositoryRoot, localRoot);
    const prefix = `${absoluteRoot}${sep}`;
    counts[localRoot] = swiftPaths.filter((path) =>
      path === absoluteRoot || path.startsWith(prefix)
    ).length;
    if (counts[localRoot] === 0) {
      throw new ContractValidationError(
        `Complete iOS source scan did not cover required production root '${localRoot}'.`,
      );
    }
  }
  return counts;
}

export function validateContractDefinitions(): {
  readonly model: ContractPathReport;
  readonly wire: ContractPathReport;
  readonly generatedStructNames: readonly string[];
} {
  assertFiniteNumericContracts(merianModelContract, "Model contract");
  assertFiniteNumericContracts(
    merianDescribeModelContract,
    "Describe model contract",
  );
  assertFiniteNumericContracts(
    identifyWireEnvelopeContract,
    "Wire contract",
  );
  const model = collectContractPaths(merianModelContract);
  const describeModel = collectContractPaths(merianDescribeModelContract);
  const wire = collectContractPaths(identifyWireEnvelopeContract);
  assertRequiredPaths(model, REQUIRED_MODEL_PATHS, "Model contract");
  assertRequiredPaths(
    describeModel,
    REQUIRED_MODEL_PATHS,
    "Describe model contract",
  );
  assertRequiredPaths(wire, REQUIRED_WIRE_PATHS, "Wire contract");

  const expectedIgnored = [
    "data.ai_reasoning",
    "data.extracted_visual_traits",
  ];
  const actualIgnored = [...wire.ignoredSwiftPaths].sort();
  if (JSON.stringify(actualIgnored) !== JSON.stringify(expectedIgnored)) {
    throw new ContractValidationError(
      `Unexpected Swift-ignored wire paths: ${
        actualIgnored.join(", ") || "<none>"
      }.`,
    );
  }

  // Exhaustively exercise provider projection now, so an unsupported contract
  // discriminant cannot silently produce a partial model schema.
  providerSchemaFromContract(merianModelContract);
  providerSchemaFromContract(merianDescribeModelContract);
  const generatedStructNames = [
    ...collectSwiftObjects(identifyWireEnvelopeContract).keys(),
  ].sort();
  return { model, wire, generatedStructNames };
}

export async function validateAPIContracts(): Promise<
  ContractValidationReport
> {
  const definitions = validateContractDefinitions();
  let swiftPaths: string[];
  let canonicalSource: string;
  try {
    swiftPaths = await discoverSwiftSourcePaths(iosSourceGraphRoot);
    canonicalSource = await Deno.readTextFile(canonicalSwiftDTOPath);
  } catch (error) {
    throw new ContractValidationError(
      `Contract source read failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }
  if (!swiftPaths.includes(canonicalSwiftDTOPath)) {
    throw new ContractValidationError(
      "Complete iOS source scan did not include InferenceEdgeDTOs.swift.",
    );
  }
  validateGeneratedSwiftSource(canonicalSource);

  const sourceEntries = await Promise.all(
    swiftPaths.map(async (path) => ({
      path,
      source: await Deno.readTextFile(path),
    })),
  );
  validateSwiftSourceOwnership(sourceEntries);
  const rootCounts = productionRootCounts(swiftPaths);
  const numericPaths = new Set([
    ...definitions.model.numericPaths,
    ...definitions.wire.numericPaths,
  ]);

  return {
    generatedStructNames: definitions.generatedStructNames,
    modelPathCount: definitions.model.paths.size,
    wirePathCount: definitions.wire.paths.size,
    numericPathCount: numericPaths.size,
    ignoredSwiftPaths: [...definitions.wire.ignoredSwiftPaths].sort(),
    swiftSourceCount: swiftPaths.length,
    productionSourceRootCounts: rootCounts,
  };
}

function displayPath(path: string): string {
  const local = relative(repositoryRoot, path);
  return local.startsWith("..") ? path : local;
}

async function main(): Promise<void> {
  const unknownArguments = Deno.args.filter((argument) =>
    argument !== "--write-swift"
  );
  if (unknownArguments.length > 0) {
    throw new ContractValidationError(
      `Unknown argument(s): ${unknownArguments.join(", ")}.`,
    );
  }
  if (Deno.args.includes("--write-swift")) {
    const source = await Deno.readTextFile(canonicalSwiftDTOPath);
    const generated = replaceGeneratedSwiftDTOBlock(source);
    await Deno.writeTextFile(canonicalSwiftDTOPath, generated);
    console.log(`Regenerated ${displayPath(canonicalSwiftDTOPath)}.`);
  }

  console.log("Starting executable Identify wire-contract validation.");
  console.log(`Contract: ${displayPath(canonicalContractPath)}`);
  console.log(`Swift:    ${displayPath(canonicalSwiftDTOPath)}`);
  const report = await validateAPIContracts();
  console.log(
    `Validated ${report.modelPathCount} model paths, ${report.wirePathCount} final wire paths, ${report.numericPathCount} bounded numeric paths, and ${report.generatedStructNames.length} generated Swift DTO structs.`,
  );
  console.log(
    `Scanned ${report.swiftSourceCount} Swift files under apps/ios; production roots: ${
      Object.entries(report.productionSourceRootCounts)
        .map(([root, count]) => `${root}=${count}`)
        .join(", ")
    }.`,
  );
  console.log(
    `Intentional Swift-ignored wire fields: ${
      report.ignoredSwiftPaths.join(", ")
    }.`,
  );
  console.log("Executable Identify wire-contract validation passed.");
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
