/**
 * Merian Identify Edge DTO contract validator.
 *
 * Parses the canonical Gemini response schema with the TypeScript compiler AST,
 * follows local object factories/spreads, and verifies that every top-level
 * client-visible schema field is represented by the iOS Codable boundary.
 *
 * Run from any directory:
 * deno run --frozen --config services/supabase/scripts/validate_edge_dtos.deno.json \
 *   --allow-env \
 *   --allow-read=services/supabase/functions/_shared/identify/schema.ts,apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift \
 *   services/supabase/scripts/validate_edge_dtos.ts
 */

import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import * as ts from "typescript";

export const IDENTIFY_SCHEMA_EXPORT = "getMerianResponseSchema";
export const MIN_IDENTIFY_SCHEMA_PROPERTIES = 30;
export const MIN_IDENTIFY_TOP_LEVEL_PROPERTIES = 20;
export const MIN_SWIFT_DTO_PROPERTIES = 34;
export const SWIFT_RESPONSE_STRUCT = "EdgeResponse";

export const REQUIRED_IDENTIFY_TOP_LEVEL_PROPERTIES = [
  "is_biological_subject",
  "scientific_name",
  "confidence_score",
  "candidates",
  "image_quality",
  "pet_identification",
  "ecological_interactions",
] as const;

/**
 * These values are intentionally present in the generated top-level object but
 * are not direct EdgeResponse fields: reasoning is delivered under insight_data
 * and visual traits are persisted server-side. Unknown JSON keys are safely
 * ignored by Swift's synthesized Decodable implementation.
 */
export const INTENTIONALLY_SERVER_ONLY_SCHEMA_PROPERTIES = new Set([
  "ai_reasoning",
  "extracted_visual_traits",
]);

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = resolve(scriptDirectory, "../../..");

export const canonicalIdentifySchemaPath = resolve(
  repositoryRoot,
  "services/supabase/functions/_shared/identify/schema.ts",
);
export const inferenceEdgeDTOsPath = resolve(
  repositoryRoot,
  "apps/ios/Merian/Core/AI/InferenceEdgeDTOs.swift",
);

export class ContractValidationError extends Error {
  override name = "ContractValidationError";
}

export interface SchemaContract {
  readonly allProperties: ReadonlySet<string>;
  readonly topLevelProperties: ReadonlySet<string>;
  readonly propertyPaths: ReadonlySet<string>;
  readonly resolvedRootCount: number;
}

export interface ContractValidationPolicy {
  readonly minimumSchemaProperties: number;
  readonly minimumTopLevelSchemaProperties: number;
  readonly minimumSwiftProperties: number;
  readonly requiredTopLevelProperties: readonly string[];
  readonly intentionallyServerOnlyProperties: ReadonlySet<string>;
}

export interface ContractValidationReport {
  readonly schemaContract: SchemaContract;
  readonly swiftProperties: ReadonlySet<string>;
  readonly intentionallyServerOnlyProperties: readonly string[];
}

export interface ContractPaths {
  readonly schemaPath: string;
  readonly swiftPath: string;
}

export const defaultValidationPolicy: ContractValidationPolicy = {
  minimumSchemaProperties: MIN_IDENTIFY_SCHEMA_PROPERTIES,
  minimumTopLevelSchemaProperties: MIN_IDENTIFY_TOP_LEVEL_PROPERTIES,
  minimumSwiftProperties: MIN_SWIFT_DTO_PROPERTIES,
  requiredTopLevelProperties: REQUIRED_IDENTIFY_TOP_LEVEL_PROPERTIES,
  intentionallyServerOnlyProperties:
    INTENTIONALLY_SERVER_ONLY_SCHEMA_PROPERTIES,
};

interface AstIndex {
  readonly initializers: Map<string, ts.Expression>;
}

interface MutableSchemaContract {
  readonly allProperties: Set<string>;
  readonly topLevelProperties: Set<string>;
  readonly propertyPaths: Set<string>;
}

function syntaxDiagnostics(
  sourceFile: ts.SourceFile,
): readonly ts.Diagnostic[] {
  const parsed = sourceFile as ts.SourceFile & {
    readonly parseDiagnostics?: readonly ts.Diagnostic[];
  };
  return parsed.parseDiagnostics ?? [];
}

function formatDiagnostic(
  sourceFile: ts.SourceFile,
  diagnostic: ts.Diagnostic,
): string {
  const message = ts.flattenDiagnosticMessageText(
    diagnostic.messageText,
    "\n",
  );
  if (diagnostic.start === undefined) {
    return `${sourceFile.fileName}: ${message}`;
  }
  const location = sourceFile.getLineAndCharacterOfPosition(diagnostic.start);
  return `${sourceFile.fileName}:${location.line + 1}:${
    location.character + 1
  }: ${message}`;
}

function buildAstIndex(sourceFile: ts.SourceFile): AstIndex {
  const initializers = new Map<string, ts.Expression>();

  const visit = (node: ts.Node): void => {
    if (
      ts.isVariableDeclaration(node) &&
      ts.isIdentifier(node.name) &&
      node.initializer
    ) {
      initializers.set(node.name.text, node.initializer);
    }
    ts.forEachChild(node, visit);
  };

  visit(sourceFile);
  return { initializers };
}

function unwrapExpression(expression: ts.Expression): ts.Expression {
  let current = expression;
  while (
    ts.isParenthesizedExpression(current) ||
    ts.isAsExpression(current) ||
    ts.isTypeAssertionExpression(current) ||
    ts.isSatisfiesExpression(current) ||
    ts.isNonNullExpression(current)
  ) {
    current = current.expression;
  }
  return current;
}

function returnedExpressions(
  declaration: ts.ArrowFunction | ts.FunctionExpression,
): ts.Expression[] {
  if (ts.isArrowFunction(declaration) && !ts.isBlock(declaration.body)) {
    return [declaration.body];
  }

  const expressions: ts.Expression[] = [];
  const body = declaration.body;
  const visit = (node: ts.Node): void => {
    if (node !== body && ts.isFunctionLike(node)) return;
    if (ts.isReturnStatement(node) && node.expression) {
      expressions.push(node.expression);
      return;
    }
    ts.forEachChild(node, visit);
  };
  visit(body);
  return expressions;
}

function resolveObjectLiteral(
  expression: ts.Expression,
  index: AstIndex,
  resolvingIdentifiers = new Set<string>(),
): ts.ObjectLiteralExpression | undefined {
  const current = unwrapExpression(expression);
  if (ts.isObjectLiteralExpression(current)) return current;

  if (ts.isIdentifier(current)) {
    if (resolvingIdentifiers.has(current.text)) return undefined;
    const initializer = index.initializers.get(current.text);
    if (!initializer) return undefined;

    const nextIdentifiers = new Set(resolvingIdentifiers);
    nextIdentifiers.add(current.text);
    return resolveObjectLiteral(initializer, index, nextIdentifiers);
  }

  if (ts.isCallExpression(current) && ts.isIdentifier(current.expression)) {
    const initializer = index.initializers.get(current.expression.text);
    if (!initializer) return undefined;

    const target = unwrapExpression(initializer);
    if (!ts.isArrowFunction(target) && !ts.isFunctionExpression(target)) {
      return undefined;
    }

    for (const returned of returnedExpressions(target).reverse()) {
      const resolved = resolveObjectLiteral(
        returned,
        index,
        new Set(resolvingIdentifiers),
      );
      if (resolved) return resolved;
    }
  }

  return undefined;
}

function propertyNameText(name: ts.PropertyName): string | undefined {
  if (
    ts.isIdentifier(name) ||
    ts.isStringLiteral(name) ||
    ts.isNumericLiteral(name)
  ) {
    return name.text;
  }
  if (
    ts.isComputedPropertyName(name) &&
    ts.isStringLiteral(name.expression)
  ) {
    return name.expression.text;
  }
  return undefined;
}

function propertyAssignment(
  object: ts.ObjectLiteralExpression,
  name: string,
): ts.PropertyAssignment | undefined {
  return object.properties.find((property) =>
    ts.isPropertyAssignment(property) &&
    propertyNameText(property.name) === name
  ) as ts.PropertyAssignment | undefined;
}

function collectNestedSchemaProperties(
  expression: ts.Expression,
  parentPath: string,
  index: AstIndex,
  contract: MutableSchemaContract,
): void {
  const object = resolveObjectLiteral(expression, index);
  if (!object) {
    throw new ContractValidationError(
      `Unable to statically resolve a schema definition at '${parentPath}'.`,
    );
  }

  for (const member of object.properties) {
    if (ts.isSpreadAssignment(member)) {
      collectNestedSchemaProperties(
        member.expression,
        parentPath,
        index,
        contract,
      );
      continue;
    }
    if (!ts.isPropertyAssignment(member)) continue;

    const name = propertyNameText(member.name);
    if (name === "properties") {
      collectPropertyMap(
        member.initializer,
        parentPath,
        false,
        index,
        contract,
      );
    } else if (name === "items") {
      collectNestedSchemaProperties(
        member.initializer,
        `${parentPath}[]`,
        index,
        contract,
      );
    } else if (name === "anyOf" || name === "oneOf" || name === "allOf") {
      const variants = unwrapExpression(member.initializer);
      if (!ts.isArrayLiteralExpression(variants)) {
        throw new ContractValidationError(
          `Unable to statically resolve schema composition at '${parentPath}'.`,
        );
      }
      for (const variant of variants.elements) {
        collectNestedSchemaProperties(
          variant,
          parentPath,
          index,
          contract,
        );
      }
    }
  }
}

function collectPropertyMap(
  expression: ts.Expression,
  parentPath: string,
  topLevel: boolean,
  index: AstIndex,
  contract: MutableSchemaContract,
): void {
  const propertyMap = resolveObjectLiteral(expression, index);
  if (!propertyMap) {
    throw new ContractValidationError(
      `Unable to statically resolve a schema properties object at '${
        parentPath || "<root>"
      }'.`,
    );
  }

  for (const member of propertyMap.properties) {
    if (ts.isSpreadAssignment(member)) {
      collectPropertyMap(
        member.expression,
        parentPath,
        topLevel,
        index,
        contract,
      );
      continue;
    }

    if (!ts.isPropertyAssignment(member)) {
      throw new ContractValidationError(
        `Unsupported schema member '${member.getText()}' at '${
          parentPath || "<root>"
        }'.`,
      );
    }

    const name = propertyNameText(member.name);
    if (!name) {
      throw new ContractValidationError(
        `Unable to resolve computed schema property '${member.name.getText()}'.`,
      );
    }

    const path = parentPath ? `${parentPath}.${name}` : name;
    contract.allProperties.add(name);
    contract.propertyPaths.add(path);
    if (topLevel) contract.topLevelProperties.add(name);

    collectNestedSchemaProperties(
      member.initializer,
      path,
      index,
      contract,
    );
  }
}

function rootSchemaObjects(
  sourceFile: ts.SourceFile,
  index: AstIndex,
  exportName: string,
): ts.ObjectLiteralExpression[] {
  const initializer = index.initializers.get(exportName);
  if (!initializer) {
    throw new ContractValidationError(
      `Canonical schema export '${exportName}' was not found in ${sourceFile.fileName}.`,
    );
  }

  const target = unwrapExpression(initializer);
  if (!ts.isArrowFunction(target) && !ts.isFunctionExpression(target)) {
    throw new ContractValidationError(
      `Canonical schema export '${exportName}' is not a function.`,
    );
  }

  const roots: ts.ObjectLiteralExpression[] = [];
  for (const returned of returnedExpressions(target)) {
    const root = resolveObjectLiteral(returned, index);
    if (root && propertyAssignment(root, "properties")) roots.push(root);
  }

  if (roots.length === 0) {
    throw new ContractValidationError(
      `No statically resolvable root properties object was returned by '${exportName}'.`,
    );
  }
  return roots;
}

export function extractSchemaContract(
  source: string,
  fileName = "schema.ts",
  exportName = IDENTIFY_SCHEMA_EXPORT,
): SchemaContract {
  const sourceFile = ts.createSourceFile(
    fileName,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const diagnostics = syntaxDiagnostics(sourceFile);
  if (diagnostics.length > 0) {
    throw new ContractValidationError(
      `TypeScript schema could not be parsed:\n${
        diagnostics.map((diagnostic) =>
          formatDiagnostic(sourceFile, diagnostic)
        ).join("\n")
      }`,
    );
  }

  const index = buildAstIndex(sourceFile);
  const roots = rootSchemaObjects(sourceFile, index, exportName);
  const mutable: MutableSchemaContract = {
    allProperties: new Set(),
    topLevelProperties: new Set(),
    propertyPaths: new Set(),
  };

  for (const root of roots) {
    const properties = propertyAssignment(root, "properties");
    if (!properties) continue;
    collectPropertyMap(
      properties.initializer,
      "",
      true,
      index,
      mutable,
    );
  }

  return {
    ...mutable,
    resolvedRootCount: roots.length,
  };
}

export function extractSwiftProperties(source: string): ReadonlySet<string> {
  const withoutComments = source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/\/\/.*$/gm, "");
  const structPattern = new RegExp(
    `\\bstruct\\s+${SWIFT_RESPONSE_STRUCT}\\b[^\\{]*\\{`,
  );
  const structMatch = structPattern.exec(withoutComments);
  if (!structMatch) {
    throw new ContractValidationError(
      `Swift response struct '${SWIFT_RESPONSE_STRUCT}' was not found.`,
    );
  }

  const openingBrace = structMatch.index + structMatch[0].lastIndexOf("{");
  let depth = 1;
  let directBody = "";
  let closed = false;
  for (let index = openingBrace + 1; index < withoutComments.length; index++) {
    const character = withoutComments[index];
    if (character === "{") {
      depth++;
      continue;
    }
    if (character === "}") {
      depth--;
      if (depth === 0) {
        closed = true;
        break;
      }
      continue;
    }
    if (depth === 1) {
      directBody += character;
    } else if (character === "\n") {
      directBody += "\n";
    }
  }
  if (!closed) {
    throw new ContractValidationError(
      `Swift response struct '${SWIFT_RESPONSE_STRUCT}' has unbalanced braces.`,
    );
  }

  const declaration = /\blet\s+(?:`([^`]+)`|([A-Za-z_][A-Za-z0-9_]*))\s*:/g;
  const properties = new Set<string>();

  for (const match of directBody.matchAll(declaration)) {
    properties.add(match[1] ?? match[2]);
  }
  return properties;
}

function coverageFailures(
  schema: SchemaContract,
  swiftProperties: ReadonlySet<string>,
  policy: ContractValidationPolicy,
): string[] {
  const failures: string[] = [];

  if (schema.allProperties.size < policy.minimumSchemaProperties) {
    failures.push(
      `resolved ${schema.allProperties.size} unique schema properties; expected at least ${policy.minimumSchemaProperties}`,
    );
  }
  if (
    schema.topLevelProperties.size <
      policy.minimumTopLevelSchemaProperties
  ) {
    failures.push(
      `resolved ${schema.topLevelProperties.size} top-level schema properties; expected at least ${policy.minimumTopLevelSchemaProperties}`,
    );
  }
  if (swiftProperties.size < policy.minimumSwiftProperties) {
    failures.push(
      `resolved ${swiftProperties.size} Swift DTO properties; expected at least ${policy.minimumSwiftProperties}`,
    );
  }

  for (const required of policy.requiredTopLevelProperties) {
    if (!schema.topLevelProperties.has(required)) {
      failures.push(
        `required top-level schema property '${required}' is missing`,
      );
    }
  }
  return failures;
}

export function validateContractSources(
  schemaSource: string,
  swiftSource: string,
  policy: ContractValidationPolicy = defaultValidationPolicy,
  schemaFileName = "schema.ts",
): ContractValidationReport {
  const schemaContract = extractSchemaContract(
    schemaSource,
    schemaFileName,
  );
  const swiftProperties = extractSwiftProperties(swiftSource);
  const assuranceFailures = coverageFailures(
    schemaContract,
    swiftProperties,
    policy,
  );
  if (assuranceFailures.length > 0) {
    throw new ContractValidationError(
      `Contract extraction failed closed:\n${
        assuranceFailures.map((failure) => `- ${failure}`).join("\n")
      }`,
    );
  }

  const mismatches = [...schemaContract.topLevelProperties]
    .filter((property) =>
      !swiftProperties.has(property) &&
      !policy.intentionallyServerOnlyProperties.has(property)
    )
    .sort();
  if (mismatches.length > 0) {
    throw new ContractValidationError(
      `TypeScript schema fields have no matching Swift DTO property:\n${
        mismatches.map((property) =>
          `- '${property}' has no matching 'let ${property}: Type' declaration`
        ).join("\n")
      }`,
    );
  }

  return {
    schemaContract,
    swiftProperties,
    intentionallyServerOnlyProperties: [...schemaContract.topLevelProperties]
      .filter((property) =>
        policy.intentionallyServerOnlyProperties.has(property)
      )
      .sort(),
  };
}

export async function validateAPIContracts(
  paths: ContractPaths = {
    schemaPath: canonicalIdentifySchemaPath,
    swiftPath: inferenceEdgeDTOsPath,
  },
  policy: ContractValidationPolicy = defaultValidationPolicy,
): Promise<ContractValidationReport> {
  let schemaSource: string;
  let swiftSource: string;
  try {
    [schemaSource, swiftSource] = await Promise.all([
      Deno.readTextFile(paths.schemaPath),
      Deno.readTextFile(paths.swiftPath),
    ]);
  } catch (error) {
    throw new ContractValidationError(
      `Contract source read failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }

  return validateContractSources(
    schemaSource,
    swiftSource,
    policy,
    paths.schemaPath,
  );
}

function displayPath(path: string): string {
  const local = relative(repositoryRoot, path);
  return local.startsWith("..") ? path : local;
}

async function main(): Promise<void> {
  console.log("Starting Identify Edge DTO contract validation.");
  console.log(`Schema: ${displayPath(canonicalIdentifySchemaPath)}`);
  console.log(`Swift:  ${displayPath(inferenceEdgeDTOsPath)}`);

  const report = await validateAPIContracts();
  console.log(
    `Resolved ${report.schemaContract.allProperties.size} unique TypeScript schema properties ` +
      `(${report.schemaContract.topLevelProperties.size} top-level) against ` +
      `${report.swiftProperties.size} Swift ${SWIFT_RESPONSE_STRUCT} properties.`,
  );
  if (report.intentionallyServerOnlyProperties.length > 0) {
    console.log(
      `Explicit server-only fields: ${
        report.intentionallyServerOnlyProperties.join(", ")
      }.`,
    );
  }
  console.log("Identify Edge DTO contract validation passed.");
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(
      error instanceof Error ? error.message : String(error),
    );
    Deno.exit(1);
  }
}
