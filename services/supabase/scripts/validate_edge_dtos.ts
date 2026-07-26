/**
 * Merian Identify Edge DTO contract validator.
 *
 * Parses the canonical Gemini response schema with the TypeScript compiler AST,
 * follows local object factories/spreads, and structurally verifies every
 * client-visible schema field against the iOS Codable boundary, including
 * nested objects, arrays, requiredness, nullability, and coding-key aliases.
 *
 * Run from any directory:
 * deno run --frozen --config services/supabase/scripts/validate_edge_dtos.deno.json \
 *   --allow-env \
 *   --allow-read=services/supabase/functions/_shared/identify/schema.ts,apps/ios/Merian \
 *   services/supabase/scripts/validate_edge_dtos.ts
 */

import { dirname, join, relative, resolve } from "node:path";
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

/**
 * The Gemini response schema is only one input to the final Identify response.
 * These Swift fields are deliberately added by the server from request
 * telemetry, cache hydration, moderation, or post-model enrichment.
 */
export const INTENTIONALLY_SERVER_ADDED_SWIFT_PATHS = new Set([
  "alternative_common_names",
  "blur_score",
  "colors",
  "estimated_size_cm",
  "gbif_taxon_key",
  "group_tags",
  "insight_data",
  "inference_tier",
  "is_new_to_merian_dictionary",
  "iucn_red_list_status",
  "reference_image_url",
  "scan_id",
  "species_insights",
  "taxonomy",
  "wikipedia_overview",
  "wikipedia_url",
  "candidates[].common_name",
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
export const iosApplicationSwiftRootPath = resolve(
  repositoryRoot,
  "apps/ios/Merian",
);

export class ContractValidationError extends Error {
  override name = "ContractValidationError";
}

export interface SchemaContract {
  readonly allProperties: ReadonlySet<string>;
  readonly topLevelProperties: ReadonlySet<string>;
  readonly propertyPaths: ReadonlySet<string>;
  readonly resolvedRootCount: number;
  readonly root: SchemaNode;
}

export type SchemaKind =
  | "array"
  | "boolean"
  | "integer"
  | "number"
  | "object"
  | "string";

export interface SchemaNode {
  readonly path: string;
  readonly kind: SchemaKind;
  readonly required: boolean;
  readonly nullable: boolean;
  readonly minimum?: number;
  readonly maximum?: number;
  readonly properties: ReadonlyMap<string, SchemaNode>;
  readonly items?: SchemaNode;
}

export type SwiftType =
  | {
    readonly kind: "array";
    readonly optional: boolean;
    readonly element: SwiftType;
  }
  | {
    readonly kind: "dictionary";
    readonly optional: boolean;
    readonly key: SwiftType;
    readonly value: SwiftType;
  }
  | {
    readonly kind: "named";
    readonly optional: boolean;
    readonly name: string;
  };

export interface SwiftProperty {
  readonly name: string;
  readonly jsonNames: ReadonlySet<string>;
  readonly type: SwiftType;
}

export interface SwiftStruct {
  readonly name: string;
  readonly fullName: string;
  readonly parentFullName?: string;
  readonly properties: ReadonlyMap<string, SwiftProperty>;
  readonly hasCustomDecoder: boolean;
  readonly unsupportedCodingKeyEnums: readonly string[];
}

export interface SwiftContract {
  readonly root: SwiftStruct;
  readonly structs: ReadonlyMap<string, SwiftStruct>;
  readonly propertyPaths: ReadonlySet<string>;
}

export interface ContractValidationPolicy {
  readonly minimumSchemaProperties: number;
  readonly minimumTopLevelSchemaProperties: number;
  readonly minimumSwiftProperties: number;
  readonly requiredTopLevelProperties: readonly string[];
  readonly intentionallyServerOnlyProperties: ReadonlySet<string>;
  readonly intentionallyServerAddedSwiftPaths: ReadonlySet<string>;
}

export interface ContractValidationReport {
  readonly schemaContract: SchemaContract;
  readonly swiftContract: SwiftContract;
  readonly swiftProperties: ReadonlySet<string>;
  readonly validatedSchemaPaths: readonly string[];
  readonly intentionallyServerOnlyProperties: readonly string[];
  readonly intentionallyServerAddedSwiftPaths: readonly string[];
  readonly swiftExtensionSourceCount: number;
}

export interface ContractPaths {
  readonly schemaPath: string;
  readonly swiftPaths: readonly string[];
  readonly swiftExtensionSearchRoots?: readonly string[];
}

export const defaultValidationPolicy: ContractValidationPolicy = {
  minimumSchemaProperties: MIN_IDENTIFY_SCHEMA_PROPERTIES,
  minimumTopLevelSchemaProperties: MIN_IDENTIFY_TOP_LEVEL_PROPERTIES,
  minimumSwiftProperties: MIN_SWIFT_DTO_PROPERTIES,
  requiredTopLevelProperties: REQUIRED_IDENTIFY_TOP_LEVEL_PROPERTIES,
  intentionallyServerOnlyProperties:
    INTENTIONALLY_SERVER_ONLY_SCHEMA_PROPERTIES,
  intentionallyServerAddedSwiftPaths: INTENTIONALLY_SERVER_ADDED_SWIFT_PATHS,
};

interface AstIndex {
  readonly checker: ts.TypeChecker;
  readonly sourceFile: ts.SourceFile;
}

interface AstBinding {
  readonly symbol: ts.Symbol;
  readonly declaration: ts.VariableDeclaration | ts.FunctionDeclaration;
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

function buildAstIndex(
  source: string,
  fileName: string,
): { readonly sourceFile: ts.SourceFile; readonly index: AstIndex } {
  // A Program is required for lexical symbol resolution. A bare SourceFile has
  // an AST but is not bound, which is what previously forced the validator to
  // keep an unsafe global map keyed only by identifier text.
  const rootName = resolve(fileName);
  const options: ts.CompilerOptions = {
    target: ts.ScriptTarget.ESNext,
    module: ts.ModuleKind.ESNext,
    noLib: true,
    noResolve: true,
    skipLibCheck: true,
  };
  const sourceFile = ts.createSourceFile(
    rootName,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  const host = ts.createCompilerHost(options, true);
  const isRoot = (candidate: string): boolean =>
    resolve(candidate) === rootName;
  host.fileExists = isRoot;
  host.readFile = (candidate) => isRoot(candidate) ? source : undefined;
  host.getSourceFile = (candidate) =>
    isRoot(candidate) ? sourceFile : undefined;

  const program = ts.createProgram({
    rootNames: [rootName],
    options,
    host,
  });
  const boundSourceFile = program.getSourceFile(rootName);
  if (!boundSourceFile) {
    throw new ContractValidationError(
      `TypeScript compiler could not bind ${fileName}.`,
    );
  }
  return {
    sourceFile: boundSourceFile,
    index: {
      checker: program.getTypeChecker(),
      sourceFile: boundSourceFile,
    },
  };
}

function canonicalSymbol(
  symbol: ts.Symbol,
  index: AstIndex,
): ts.Symbol {
  return (symbol.flags & ts.SymbolFlags.Alias) !== 0
    ? index.checker.getAliasedSymbol(symbol)
    : symbol;
}

function astBindingForSymbol(
  symbol: ts.Symbol,
  index: AstIndex,
  description: string,
): AstBinding | undefined {
  const resolvedSymbol = canonicalSymbol(symbol, index);
  const declarations = (resolvedSymbol.declarations ?? []).filter(
    (declaration): declaration is
      | ts.VariableDeclaration
      | ts.FunctionDeclaration =>
      declaration.getSourceFile() === index.sourceFile &&
      (
        ts.isFunctionDeclaration(declaration) &&
          declaration.body !== undefined ||
        ts.isVariableDeclaration(declaration) &&
          declaration.initializer !== undefined
      ),
  );
  if (declarations.length > 1) {
    throw new ContractValidationError(
      `Ambiguous TypeScript binding '${description}' has ${declarations.length} local value declarations.`,
    );
  }
  return declarations.length === 1
    ? { symbol: resolvedSymbol, declaration: declarations[0] }
    : undefined;
}

function astBindingForIdentifier(
  identifier: ts.Identifier,
  index: AstIndex,
): AstBinding | undefined {
  const symbol = index.checker.getSymbolAtLocation(identifier);
  return symbol
    ? astBindingForSymbol(symbol, index, identifier.text)
    : undefined;
}

function bindingInitializer(
  binding: AstBinding,
): ts.Expression | ts.FunctionDeclaration {
  return ts.isVariableDeclaration(binding.declaration)
    ? binding.declaration.initializer!
    : binding.declaration;
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
  declaration:
    | ts.ArrowFunction
    | ts.FunctionDeclaration
    | ts.FunctionExpression,
): ts.Expression[] {
  if (ts.isArrowFunction(declaration) && !ts.isBlock(declaration.body)) {
    return [declaration.body];
  }

  const expressions: ts.Expression[] = [];
  const body = declaration.body;
  if (!body) return expressions;
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
  resolvingSymbols = new Set<ts.Symbol>(),
): ts.ObjectLiteralExpression | undefined {
  const current = unwrapExpression(expression);
  if (ts.isObjectLiteralExpression(current)) return current;

  if (ts.isIdentifier(current)) {
    const binding = astBindingForIdentifier(current, index);
    if (!binding) return undefined;
    if (resolvingSymbols.has(binding.symbol)) {
      throw new ContractValidationError(
        `Recursive TypeScript binding '${current.text}' cannot be resolved as an object literal.`,
      );
    }
    const initializer = bindingInitializer(binding);
    if (ts.isFunctionDeclaration(initializer)) return undefined;

    const nextSymbols = new Set(resolvingSymbols);
    nextSymbols.add(binding.symbol);
    return resolveObjectLiteral(initializer, index, nextSymbols);
  }

  if (ts.isCallExpression(current) && ts.isIdentifier(current.expression)) {
    const binding = astBindingForIdentifier(current.expression, index);
    if (!binding) return undefined;
    if (resolvingSymbols.has(binding.symbol)) {
      throw new ContractValidationError(
        `Recursive TypeScript factory '${current.expression.text}' cannot be resolved as an object literal.`,
      );
    }
    const declaration = bindingInitializer(binding);
    const target = ts.isFunctionDeclaration(declaration)
      ? declaration
      : unwrapExpression(declaration);
    if (
      !ts.isArrowFunction(target) &&
      !ts.isFunctionDeclaration(target) &&
      !ts.isFunctionExpression(target)
    ) {
      return undefined;
    }

    const nextSymbols = new Set(resolvingSymbols);
    nextSymbols.add(binding.symbol);
    for (const returned of returnedExpressions(target).reverse()) {
      const resolved = resolveObjectLiteral(
        returned,
        index,
        new Set(nextSymbols),
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

function rootSchemaObjects(
  sourceFile: ts.SourceFile,
  index: AstIndex,
  exportName: string,
): ts.ObjectLiteralExpression[] {
  const moduleSymbol = index.checker.getSymbolAtLocation(sourceFile);
  const exportedSymbols = moduleSymbol
    ? index.checker.getExportsOfModule(moduleSymbol).filter((symbol) =>
      symbol.name === exportName
    )
    : [];
  if (exportedSymbols.length === 0) {
    throw new ContractValidationError(
      `Canonical schema export '${exportName}' was not found in ${sourceFile.fileName}.`,
    );
  }
  if (exportedSymbols.length > 1) {
    throw new ContractValidationError(
      `Canonical schema export '${exportName}' is ambiguous in ${sourceFile.fileName}.`,
    );
  }
  const binding = astBindingForSymbol(
    exportedSymbols[0],
    index,
    exportName,
  );
  if (!binding) {
    throw new ContractValidationError(
      `Canonical schema export '${exportName}' has no single local value declaration.`,
    );
  }
  const declaration = bindingInitializer(binding);
  const target = ts.isFunctionDeclaration(declaration)
    ? declaration
    : unwrapExpression(declaration);
  if (
    !ts.isArrowFunction(target) &&
    !ts.isFunctionDeclaration(target) &&
    !ts.isFunctionExpression(target)
  ) {
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

function effectiveObjectAssignments(
  object: ts.ObjectLiteralExpression,
  index: AstIndex,
  path: string,
  resolvingSpreads = new Set<ts.ObjectLiteralExpression>(),
): Map<string, ts.Expression> {
  const assignments = new Map<string, ts.Expression>();
  for (const member of object.properties) {
    if (ts.isSpreadAssignment(member)) {
      const spreadKey = member.expression.getText();
      const spreadObject = resolveObjectLiteral(member.expression, index);
      if (!spreadObject) {
        throw new ContractValidationError(
          `Unable to statically resolve schema spread '${spreadKey}' at '${path}'.`,
        );
      }
      if (resolvingSpreads.has(spreadObject)) {
        throw new ContractValidationError(
          `Recursive schema spread '${spreadKey}' at '${path}'.`,
        );
      }
      const nextSpreads = new Set(resolvingSpreads);
      nextSpreads.add(spreadObject);
      for (
        const [name, expression] of effectiveObjectAssignments(
          spreadObject,
          index,
          path,
          nextSpreads,
        )
      ) {
        assignments.set(name, expression);
      }
      continue;
    }
    if (!ts.isPropertyAssignment(member)) {
      throw new ContractValidationError(
        `Unsupported schema member '${member.getText()}' at '${path}'.`,
      );
    }
    const name = propertyNameText(member.name);
    if (!name) {
      throw new ContractValidationError(
        `Unable to resolve computed schema member '${member.name.getText()}' at '${path}'.`,
      );
    }
    assignments.set(name, member.initializer);
  }
  return assignments;
}

function resolveStringArray(
  expression: ts.Expression,
  index: AstIndex,
  path: string,
  resolvingSymbols = new Set<ts.Symbol>(),
): string[] {
  const current = unwrapExpression(expression);
  if (ts.isIdentifier(current)) {
    const binding = astBindingForIdentifier(current, index);
    if (!binding) {
      throw new ContractValidationError(
        `Unable to resolve required-field definition '${current.text}' at '${path}'.`,
      );
    }
    if (resolvingSymbols.has(binding.symbol)) {
      throw new ContractValidationError(
        `Recursive required-field definition '${current.text}' at '${path}'.`,
      );
    }
    const initializer = bindingInitializer(binding);
    if (ts.isFunctionDeclaration(initializer)) {
      throw new ContractValidationError(
        `Unable to resolve required-field definition '${current.text}' at '${path}'.`,
      );
    }
    const nextSymbols = new Set(resolvingSymbols);
    nextSymbols.add(binding.symbol);
    return resolveStringArray(initializer, index, path, nextSymbols);
  }
  if (!ts.isArrayLiteralExpression(current)) {
    throw new ContractValidationError(
      `Required fields at '${path}' are not a statically resolvable string array.`,
    );
  }

  const values: string[] = [];
  for (const element of current.elements) {
    if (ts.isSpreadElement(element)) {
      values.push(
        ...resolveStringArray(
          element.expression,
          index,
          path,
          new Set(resolvingSymbols),
        ),
      );
      continue;
    }
    const value = unwrapExpression(element as ts.Expression);
    if (
      !ts.isStringLiteral(value) && !ts.isNoSubstitutionTemplateLiteral(value)
    ) {
      throw new ContractValidationError(
        `Required field '${element.getText()}' at '${path}' is not a string literal.`,
      );
    }
    values.push(value.text);
  }
  return values;
}

function schemaKind(
  expression: ts.Expression,
  path: string,
): SchemaKind {
  const current = unwrapExpression(expression);
  let value: string | undefined;
  if (ts.isPropertyAccessExpression(current)) {
    value = current.name.text;
  } else if (
    ts.isStringLiteral(current) ||
    ts.isNoSubstitutionTemplateLiteral(current)
  ) {
    value = current.text;
  }

  switch (value?.toUpperCase()) {
    case "ARRAY":
      return "array";
    case "BOOLEAN":
      return "boolean";
    case "INTEGER":
      return "integer";
    case "NUMBER":
      return "number";
    case "OBJECT":
      return "object";
    case "STRING":
      return "string";
    default:
      throw new ContractValidationError(
        `Unable to resolve schema type '${expression.getText()}' at '${path}'.`,
      );
  }
}

function schemaBoolean(
  expression: ts.Expression | undefined,
  path: string,
  defaultValue: boolean,
): boolean {
  if (!expression) return defaultValue;
  const current = unwrapExpression(expression);
  if (current.kind === ts.SyntaxKind.TrueKeyword) return true;
  if (current.kind === ts.SyntaxKind.FalseKeyword) return false;
  throw new ContractValidationError(
    `Unable to resolve boolean '${expression.getText()}' at '${path}'.`,
  );
}

function schemaNumber(
  expression: ts.Expression,
  index: AstIndex,
  path: string,
  resolvingSymbols = new Set<ts.Symbol>(),
): number {
  const current = unwrapExpression(expression);
  if (ts.isIdentifier(current)) {
    const binding = astBindingForIdentifier(current, index);
    if (!binding) {
      throw new ContractValidationError(
        `Unable to resolve numeric bound '${current.text}' at '${path}'.`,
      );
    }
    if (resolvingSymbols.has(binding.symbol)) {
      throw new ContractValidationError(
        `Recursive numeric bound '${current.text}' at '${path}'.`,
      );
    }
    const initializer = bindingInitializer(binding);
    if (ts.isFunctionDeclaration(initializer)) {
      throw new ContractValidationError(
        `Unable to resolve numeric bound '${current.text}' at '${path}'.`,
      );
    }
    const nextSymbols = new Set(resolvingSymbols);
    nextSymbols.add(binding.symbol);
    return schemaNumber(initializer, index, path, nextSymbols);
  }

  let value: number | undefined;
  if (ts.isNumericLiteral(current)) {
    value = Number(current.text);
  } else if (
    ts.isPrefixUnaryExpression(current) &&
    (
      current.operator === ts.SyntaxKind.MinusToken ||
      current.operator === ts.SyntaxKind.PlusToken
    ) &&
    ts.isNumericLiteral(current.operand)
  ) {
    const magnitude = Number(current.operand.text);
    value = current.operator === ts.SyntaxKind.MinusToken
      ? -magnitude
      : magnitude;
  }
  if (value === undefined || !Number.isFinite(value)) {
    throw new ContractValidationError(
      `Numeric bound '${expression.getText()}' at '${path}' is not a finite statically resolvable number.`,
    );
  }
  return value;
}

function parseSchemaNode(
  expression: ts.Expression,
  path: string,
  required: boolean,
  index: AstIndex,
): SchemaNode {
  const object = resolveObjectLiteral(expression, index);
  if (!object) {
    throw new ContractValidationError(
      `Unable to structurally resolve schema definition at '${path}'.`,
    );
  }
  const assignments = effectiveObjectAssignments(object, index, path);
  for (const composition of ["allOf", "anyOf", "oneOf"]) {
    if (assignments.has(composition)) {
      throw new ContractValidationError(
        `Schema composition '${composition}' at '${path}' is unsupported by the structural DTO gate.`,
      );
    }
  }

  const typeExpression = assignments.get("type");
  if (!typeExpression) {
    throw new ContractValidationError(
      `Schema definition at '${path}' has no statically resolvable type.`,
    );
  }
  const kind = schemaKind(typeExpression, path);
  const nullable = schemaBoolean(assignments.get("nullable"), path, false);
  for (const unsupportedBound of ["exclusiveMinimum", "exclusiveMaximum"]) {
    if (assignments.has(unsupportedBound)) {
      throw new ContractValidationError(
        `Numeric bound '${unsupportedBound}' at '${path}' is unsupported by the structural DTO gate.`,
      );
    }
  }
  const minimum = assignments.has("minimum")
    ? schemaNumber(assignments.get("minimum")!, index, path)
    : undefined;
  const maximum = assignments.has("maximum")
    ? schemaNumber(assignments.get("maximum")!, index, path)
    : undefined;
  if (
    minimum !== undefined &&
    maximum !== undefined &&
    minimum > maximum
  ) {
    throw new ContractValidationError(
      `Numeric bounds at '${path}' are inverted (${minimum} > ${maximum}).`,
    );
  }
  if (
    (kind === "integer" || kind === "number") &&
    (minimum === undefined || maximum === undefined)
  ) {
    throw new ContractValidationError(
      `Numeric schema at '${path}' must declare finite minimum and maximum bounds.`,
    );
  }
  if (kind === "integer") {
    if (!Number.isSafeInteger(minimum) || !Number.isSafeInteger(maximum)) {
      throw new ContractValidationError(
        `Integer bounds at '${path}' must be JavaScript safe integers.`,
      );
    }
  } else if (
    kind !== "number" &&
    (minimum !== undefined || maximum !== undefined)
  ) {
    throw new ContractValidationError(
      `Non-numeric schema at '${path}' unexpectedly declares numeric bounds.`,
    );
  }
  const properties = new Map<string, SchemaNode>();
  let items: SchemaNode | undefined;

  if (kind === "object") {
    const propertiesExpression = assignments.get("properties");
    if (!propertiesExpression) {
      throw new ContractValidationError(
        `Object schema at '${path}' has no properties definition.`,
      );
    }
    const propertyMap = resolveObjectLiteral(propertiesExpression, index);
    if (!propertyMap) {
      throw new ContractValidationError(
        `Unable to structurally resolve object properties at '${path}'.`,
      );
    }
    const propertyAssignments = effectiveObjectAssignments(
      propertyMap,
      index,
      path,
    );
    const requiredNames = new Set(
      assignments.has("required")
        ? resolveStringArray(
          assignments.get("required")!,
          index,
          path,
        )
        : [],
    );
    for (const requiredName of requiredNames) {
      if (!propertyAssignments.has(requiredName)) {
        throw new ContractValidationError(
          `Required field '${requiredName}' is absent from properties at '${path}'.`,
        );
      }
    }
    for (const [name, childExpression] of propertyAssignments) {
      const childPath = path ? `${path}.${name}` : name;
      properties.set(
        name,
        parseSchemaNode(
          childExpression,
          childPath,
          requiredNames.has(name),
          index,
        ),
      );
    }
  } else if (kind === "array") {
    const itemsExpression = assignments.get("items");
    if (!itemsExpression) {
      throw new ContractValidationError(
        `Array schema at '${path}' has no items definition.`,
      );
    }
    items = parseSchemaNode(itemsExpression, `${path}[]`, true, index);
  } else if (assignments.has("properties") || assignments.has("items")) {
    throw new ContractValidationError(
      `Primitive schema at '${path}' unexpectedly declares nested content.`,
    );
  }

  return {
    path,
    kind,
    required,
    nullable,
    ...(minimum !== undefined ? { minimum } : {}),
    ...(maximum !== undefined ? { maximum } : {}),
    properties,
    ...(items ? { items } : {}),
  };
}

function structuralSignature(node: SchemaNode): string {
  return JSON.stringify({
    kind: node.kind,
    required: node.required,
    nullable: node.nullable,
    minimum: node.minimum,
    maximum: node.maximum,
    properties: [...node.properties]
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([name, child]) => [name, structuralSignature(child)]),
    items: node.items ? structuralSignature(node.items) : undefined,
  });
}

function collectSchemaCoverage(
  node: SchemaNode,
  contract: MutableSchemaContract,
): void {
  for (const [name, child] of node.properties) {
    contract.allProperties.add(name);
    contract.propertyPaths.add(child.path);
    if (node.path === "") contract.topLevelProperties.add(name);
    collectSchemaCoverage(child, contract);
  }
  if (node.items) collectSchemaCoverage(node.items, contract);
}

export function extractSchemaContract(
  source: string,
  fileName = "schema.ts",
  exportName = IDENTIFY_SCHEMA_EXPORT,
): SchemaContract {
  const { sourceFile, index } = buildAstIndex(source, fileName);
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

  const roots = rootSchemaObjects(sourceFile, index, exportName);
  const structuralRoots = roots.map((root) =>
    parseSchemaNode(root, "", true, index)
  );
  const firstSignature = structuralSignature(structuralRoots[0]);
  for (const root of structuralRoots.slice(1)) {
    if (structuralSignature(root) !== firstSignature) {
      throw new ContractValidationError(
        `Canonical schema export '${exportName}' returns structurally different DTO roots.`,
      );
    }
  }

  const mutable: MutableSchemaContract = {
    allProperties: new Set(),
    topLevelProperties: new Set(),
    propertyPaths: new Set(),
  };
  collectSchemaCoverage(structuralRoots[0], mutable);

  return {
    ...mutable,
    resolvedRootCount: roots.length,
    root: structuralRoots[0],
  };
}

interface SwiftStructRange {
  readonly name: string;
  readonly declarationStart: number;
  readonly openingBrace: number;
  readonly closingBrace: number;
  parent?: SwiftStructRange;
  fullName?: string;
}

interface SwiftExtensionRange {
  readonly targetName: string;
  readonly openingBrace: number;
  readonly closingBrace: number;
}

interface SwiftExtensionFacts {
  readonly targetName: string;
  readonly hasCustomDecoder: boolean;
  readonly codingKeyEnums: readonly string[];
}

interface CodingKeyDefinition {
  readonly enumName: string;
  readonly keys: ReadonlyMap<string, string>;
}

function stripSwiftComments(source: string): string {
  let result = "";
  let index = 0;
  let blockDepth = 0;
  let inLineComment = false;
  let inString = false;
  let inMultilineString = false;
  let escaped = false;

  while (index < source.length) {
    const character = source[index];
    const next = source[index + 1];
    const triple = source.slice(index, index + 3) === '"""';
    if (inMultilineString) {
      if (triple) {
        inMultilineString = false;
        result += "   ";
        index += 3;
      } else {
        result += character === "\n" ? "\n" : " ";
        index++;
      }
      continue;
    }
    if (inLineComment) {
      if (character === "\n") {
        inLineComment = false;
        result += "\n";
      } else {
        result += " ";
      }
      index++;
      continue;
    }
    if (blockDepth > 0) {
      if (character === "/" && next === "*") {
        blockDepth++;
        result += "  ";
        index += 2;
      } else if (character === "*" && next === "/") {
        blockDepth--;
        result += "  ";
        index += 2;
      } else {
        result += character === "\n" ? "\n" : " ";
        index++;
      }
      continue;
    }
    if (inString) {
      result += character;
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
      index++;
      continue;
    }
    if (character === "/" && next === "/") {
      inLineComment = true;
      result += "  ";
      index += 2;
      continue;
    }
    if (character === "/" && next === "*") {
      blockDepth = 1;
      result += "  ";
      index += 2;
      continue;
    }
    if (triple) {
      inMultilineString = true;
      result += "   ";
      index += 3;
      continue;
    }
    if (character === '"') inString = true;
    result += character;
    index++;
  }

  if (blockDepth > 0 || inString || inMultilineString) {
    throw new ContractValidationError(
      "Swift DTO source has an unterminated comment or string literal.",
    );
  }
  return result;
}

function maskSwiftCommentsAndStrings(source: string): string {
  let result = "";
  let index = 0;
  let blockCommentDepth = 0;
  let inLineComment = false;
  let stringHashCount: number | undefined;
  let multilineString = false;

  const masked = (text: string): string => text.replace(/[^\n]/g, " ");

  while (index < source.length) {
    const character = source[index];
    const next = source[index + 1];

    if (inLineComment) {
      result += character === "\n" ? "\n" : " ";
      index++;
      if (character === "\n") inLineComment = false;
      continue;
    }

    if (blockCommentDepth > 0) {
      if (character === "/" && next === "*") {
        blockCommentDepth++;
        result += "  ";
        index += 2;
      } else if (character === "*" && next === "/") {
        blockCommentDepth--;
        result += "  ";
        index += 2;
      } else {
        result += character === "\n" ? "\n" : " ";
        index++;
      }
      continue;
    }

    if (stringHashCount !== undefined) {
      const closingDelimiter = `${multilineString ? '"""' : '"'}${
        "#".repeat(stringHashCount)
      }`;
      if (source.startsWith(closingDelimiter, index)) {
        result += masked(closingDelimiter);
        index += closingDelimiter.length;
        stringHashCount = undefined;
        multilineString = false;
        continue;
      }
      if (stringHashCount === 0 && character === "\\") {
        const escapedText = source.slice(index, index + 2);
        result += masked(escapedText);
        index += escapedText.length;
        continue;
      }
      result += character === "\n" ? "\n" : " ";
      index++;
      continue;
    }

    if (character === "/" && next === "/") {
      inLineComment = true;
      result += "  ";
      index += 2;
      continue;
    }
    if (character === "/" && next === "*") {
      blockCommentDepth = 1;
      result += "  ";
      index += 2;
      continue;
    }

    if (character === "#") {
      let hashEnd = index;
      while (source[hashEnd] === "#") hashEnd++;
      const hashCount = hashEnd - index;
      const isMultiline = source.startsWith('"""', hashEnd);
      if (isMultiline || source[hashEnd] === '"') {
        const openingDelimiter = source.slice(
          index,
          hashEnd + (isMultiline ? 3 : 1),
        );
        result += masked(openingDelimiter);
        index += openingDelimiter.length;
        stringHashCount = hashCount;
        multilineString = isMultiline;
        continue;
      }
    }

    if (source.startsWith('"""', index)) {
      result += "   ";
      index += 3;
      stringHashCount = 0;
      multilineString = true;
      continue;
    }
    if (character === '"') {
      result += " ";
      index++;
      stringHashCount = 0;
      multilineString = false;
      continue;
    }

    result += character;
    index++;
  }

  if (blockCommentDepth > 0 || stringHashCount !== undefined) {
    throw new ContractValidationError(
      "Swift source graph has an unterminated comment or string literal.",
    );
  }
  return result;
}

function matchingSwiftBrace(source: string, openingBrace: number): number {
  let depth = 1;
  let inString = false;
  let escaped = false;
  for (let index = openingBrace + 1; index < source.length; index++) {
    const character = source[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
      continue;
    }
    if (character === '"') {
      inString = true;
    } else if (character === "{") {
      depth++;
    } else if (character === "}") {
      depth--;
      if (depth === 0) return index;
    }
  }
  throw new ContractValidationError(
    `Swift declaration at offset ${openingBrace} has unbalanced braces.`,
  );
}

function swiftExtensionRanges(source: string): SwiftExtensionRange[] {
  const ranges: SwiftExtensionRange[] = [];
  const declaration = /\bextension\s+([A-Za-z_][A-Za-z0-9_.]*)\b[^{;]*\{/g;
  for (const match of source.matchAll(declaration)) {
    if (match.index === undefined) continue;
    const openingBrace = match.index + match[0].lastIndexOf("{");
    ranges.push({
      targetName: match[1],
      openingBrace,
      closingBrace: matchingSwiftBrace(source, openingBrace),
    });
  }
  return ranges;
}

function swiftStructRanges(source: string): SwiftStructRange[] {
  const ranges: SwiftStructRange[] = [];
  const declaration = /\bstruct\s+([A-Za-z_][A-Za-z0-9_]*)\b[^{]*\{/g;
  for (const match of source.matchAll(declaration)) {
    if (match.index === undefined) continue;
    const openingBrace = match.index + match[0].lastIndexOf("{");
    ranges.push({
      name: match[1],
      declarationStart: match.index,
      openingBrace,
      closingBrace: matchingSwiftBrace(source, openingBrace),
    });
  }

  for (const range of ranges) {
    range.parent = ranges
      .filter((candidate) =>
        candidate !== range &&
        candidate.openingBrace < range.declarationStart &&
        candidate.closingBrace > range.closingBrace
      )
      .sort((left, right) =>
        (left.closingBrace - left.openingBrace) -
        (right.closingBrace - right.openingBrace)
      )[0];
  }

  const fullName = (range: SwiftStructRange): string => {
    if (range.fullName) return range.fullName;
    range.fullName = range.parent
      ? `${fullName(range.parent)}.${range.name}`
      : range.name;
    return range.fullName;
  };
  for (const range of ranges) fullName(range);
  return ranges;
}

function directSwiftBody(
  source: string,
  openingBrace: number,
  closingBrace: number,
): string {
  let result = "";
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = openingBrace + 1; index < closingBrace; index++) {
    const character = source[index];
    if (inString) {
      if (depth === 0) result += character;
      else result += character === "\n" ? "\n" : " ";
      if (escaped) {
        escaped = false;
      } else if (character === "\\") {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
      continue;
    }
    if (character === '"') {
      inString = true;
      result += depth === 0 ? character : " ";
    } else if (character === "{") {
      depth++;
      result += " ";
    } else if (character === "}") {
      depth--;
      if (depth < 0) {
        throw new ContractValidationError(
          "Swift declaration body has unbalanced braces.",
        );
      }
      result += " ";
    } else if (depth === 0) {
      result += character;
    } else {
      result += character === "\n" ? "\n" : " ";
    }
  }
  return result;
}

function splitTopLevelSwiftType(
  source: string,
  separator: string,
): [string, string] | undefined {
  let squareDepth = 0;
  let angleDepth = 0;
  for (let index = 0; index < source.length; index++) {
    const character = source[index];
    if (character === "[") squareDepth++;
    else if (character === "]") squareDepth--;
    else if (character === "<") angleDepth++;
    else if (character === ">") angleDepth--;
    else if (
      character === separator &&
      squareDepth === 0 &&
      angleDepth === 0
    ) {
      return [source.slice(0, index), source.slice(index + 1)];
    }
  }
  return undefined;
}

function withSwiftOptional(type: SwiftType, optional: boolean): SwiftType {
  return { ...type, optional };
}

function parseSwiftType(source: string): SwiftType {
  let text = source.trim().replace(/\s+/g, "");
  let optional = false;
  while (text.endsWith("?") || text.endsWith("!")) {
    optional = true;
    text = text.slice(0, -1);
  }
  if (text.startsWith("Optional<") && text.endsWith(">")) {
    return withSwiftOptional(
      parseSwiftType(text.slice("Optional<".length, -1)),
      true,
    );
  }
  if (text.startsWith("[") && text.endsWith("]")) {
    const body = text.slice(1, -1);
    const dictionary = splitTopLevelSwiftType(body, ":");
    if (dictionary) {
      return {
        kind: "dictionary",
        optional,
        key: parseSwiftType(dictionary[0]),
        value: parseSwiftType(dictionary[1]),
      };
    }
    return {
      kind: "array",
      optional,
      element: parseSwiftType(body),
    };
  }
  if (text.startsWith("Array<") && text.endsWith(">")) {
    return {
      kind: "array",
      optional,
      element: parseSwiftType(text.slice("Array<".length, -1)),
    };
  }
  if (!/^[A-Za-z_][A-Za-z0-9_.]*$/.test(text)) {
    throw new ContractValidationError(
      `Unsupported Swift DTO type '${source.trim()}'.`,
    );
  }
  return { kind: "named", optional, name: text };
}

function codingKeyDefinitions(
  source: string,
  ranges: readonly SwiftStructRange[],
): Map<SwiftStructRange, CodingKeyDefinition[]> {
  const definitions = new Map<SwiftStructRange, CodingKeyDefinition[]>();
  const declaration =
    /\benum\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*[^{\n]*\bCodingKey\b[^{]*\{/g;
  for (const match of source.matchAll(declaration)) {
    if (match.index === undefined) continue;
    const openingBrace = match.index + match[0].lastIndexOf("{");
    const closingBrace = matchingSwiftBrace(source, openingBrace);
    const owner = ranges
      .filter((range) =>
        range.openingBrace < match.index &&
        range.closingBrace > closingBrace
      )
      .sort((left, right) =>
        (left.closingBrace - left.openingBrace) -
        (right.closingBrace - right.openingBrace)
      )[0];
    if (!owner) continue;

    const body = source.slice(openingBrace + 1, closingBrace);
    const keys = new Map<string, string>();
    const caseDeclaration = /\bcase\s+([^\n}]+)/g;
    for (const caseMatch of body.matchAll(caseDeclaration)) {
      for (const item of caseMatch[1].split(",")) {
        const keyMatch =
          /^\s*`?([A-Za-z_][A-Za-z0-9_]*)`?(?:\s*=\s*"([^"]*)")?\s*$/
            .exec(item);
        if (!keyMatch) {
          throw new ContractValidationError(
            `Unsupported CodingKey declaration '${item.trim()}' in ${owner.fullName}.${
              match[1]
            }.`,
          );
        }
        keys.set(keyMatch[1], keyMatch[2] ?? keyMatch[1]);
      }
    }
    const current = definitions.get(owner) ?? [];
    current.push({ enumName: match[1], keys });
    definitions.set(owner, current);
  }
  return definitions;
}

function swiftPropertiesForRange(
  source: string,
  range: SwiftStructRange,
  codingKeys: readonly CodingKeyDefinition[],
): Map<string, SwiftProperty> {
  const body = directSwiftBody(
    source,
    range.openingBrace,
    range.closingBrace,
  );
  const declarations =
    /\blet\s+(?:`([^`]+)`|([A-Za-z_][A-Za-z0-9_]*))\s*:\s*([^\n={]+)/g;
  const properties = new Map<string, SwiftProperty>();
  const declaredStandardKeys = codingKeys.find((definition) =>
    definition.enumName === "CodingKeys"
  );
  for (const match of body.matchAll(declarations)) {
    const name = match[1] ?? match[2];
    if (properties.has(name)) {
      throw new ContractValidationError(
        `Swift DTO '${range.fullName}' declares '${name}' more than once.`,
      );
    }

    const jsonNames = new Set<string>();
    if (declaredStandardKeys) {
      const standardName = declaredStandardKeys.keys.get(name);
      if (standardName) jsonNames.add(standardName);
    } else {
      jsonNames.add(name);
    }
    properties.set(name, {
      name,
      jsonNames,
      type: parseSwiftType(match[3]),
    });
  }
  return properties;
}

const customSwiftDecoderPattern =
  /\binit\s*\(\s*from\s+[A-Za-z_][A-Za-z0-9_]*\s*:\s*(?:any\s+)?(?:[A-Za-z_][A-Za-z0-9_]*\.)*Decoder\s*\)\s*throws\b/;

function hasCustomSwiftDecoderBody(body: string): boolean {
  return customSwiftDecoderPattern.test(body);
}

function hasCustomSwiftDecoder(
  source: string,
  range: SwiftStructRange,
): boolean {
  return hasCustomSwiftDecoderBody(
    directSwiftBody(
      source,
      range.openingBrace,
      range.closingBrace,
    ),
  );
}

function swiftExtensionFacts(
  sources: string | readonly string[],
): readonly SwiftExtensionFacts[] {
  const sourceList = typeof sources === "string" ? [sources] : sources;
  const facts: SwiftExtensionFacts[] = [];
  for (const originalSource of sourceList) {
    const source = maskSwiftCommentsAndStrings(originalSource);
    for (const range of swiftExtensionRanges(source)) {
      const body = directSwiftBody(
        source,
        range.openingBrace,
        range.closingBrace,
      );
      const codingKeyEnums = [...body.matchAll(
        /\benum\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*[^{\n]*\bCodingKey\b/g,
      )].map((match) => match[1]).sort();
      facts.push({
        targetName: range.targetName,
        hasCustomDecoder: hasCustomSwiftDecoderBody(body),
        codingKeyEnums,
      });
    }
  }
  return facts;
}

function extensionTargetsStruct(
  targetName: string,
  candidate: SwiftStruct,
): boolean {
  if (targetName === candidate.fullName) return true;
  if (targetName.endsWith(`.${candidate.fullName}`)) return true;
  return candidate.parentFullName === undefined &&
    !targetName.includes(".") &&
    targetName === candidate.name;
}

function resolveSwiftStruct(
  typeName: string,
  owner: SwiftStruct,
  structs: ReadonlyMap<string, SwiftStruct>,
): SwiftStruct | undefined {
  if (typeName.includes(".")) return structs.get(typeName);

  let scope: SwiftStruct | undefined = owner;
  while (scope) {
    const nested = structs.get(`${scope.fullName}.${typeName}`);
    if (nested) return nested;
    scope = scope.parentFullName
      ? structs.get(scope.parentFullName)
      : undefined;
  }
  const root = structs.get(typeName);
  if (root) return root;

  const suffixMatches = [...structs.values()].filter((candidate) =>
    candidate.fullName.endsWith(`.${typeName}`)
  );
  return suffixMatches.length === 1 ? suffixMatches[0] : undefined;
}

function collectSwiftPropertyPaths(
  root: SwiftStruct,
  structs: ReadonlyMap<string, SwiftStruct>,
): ReadonlySet<string> {
  const paths = new Set<string>();
  const visiting = new Set<string>();
  const visit = (
    owner: SwiftStruct,
    prefix: string,
  ): void => {
    if (visiting.has(owner.fullName)) return;
    visiting.add(owner.fullName);
    for (const property of owner.properties.values()) {
      const jsonName = [...property.jsonNames].sort()[0];
      if (!jsonName) continue;
      const path = prefix ? `${prefix}.${jsonName}` : jsonName;
      paths.add(path);
      let type = property.type;
      let nestedPrefix = path;
      if (type.kind === "array") {
        type = type.element;
        nestedPrefix = `${path}[]`;
      }
      if (type.kind === "named") {
        const nested = resolveSwiftStruct(type.name, owner, structs);
        if (nested) visit(nested, nestedPrefix);
      }
    }
    visiting.delete(owner.fullName);
  };
  visit(root, "");
  return paths;
}

export function extractSwiftContract(
  sources: string | readonly string[],
  extensionSources: string | readonly string[] = sources,
): SwiftContract {
  const source = stripSwiftComments(
    typeof sources === "string" ? sources : sources.join("\n"),
  );
  const extensionFacts = swiftExtensionFacts(extensionSources);
  const ranges = swiftStructRanges(source);
  const codingKeys = codingKeyDefinitions(source, ranges);
  const structs = new Map<string, SwiftStruct>();
  for (const range of ranges) {
    const fullName = range.fullName;
    if (!fullName) {
      throw new ContractValidationError(
        `Unable to resolve Swift struct name '${range.name}'.`,
      );
    }
    if (structs.has(fullName)) {
      throw new ContractValidationError(
        `Swift DTO struct '${fullName}' is declared more than once.`,
      );
    }
    const rangeCodingKeys = codingKeys.get(range) ?? [];
    structs.set(fullName, {
      name: range.name,
      fullName,
      ...(range.parent?.fullName
        ? { parentFullName: range.parent.fullName }
        : {}),
      properties: swiftPropertiesForRange(
        source,
        range,
        rangeCodingKeys,
      ),
      hasCustomDecoder: hasCustomSwiftDecoder(source, range),
      unsupportedCodingKeyEnums: rangeCodingKeys
        .map((definition) => definition.enumName)
        .filter((name) => name !== "CodingKeys")
        .sort(),
    });
  }
  for (const [fullName, candidate] of structs) {
    const matchingExtensions = extensionFacts.filter((facts) =>
      extensionTargetsStruct(facts.targetName, candidate)
    );
    const extensionCodingKeys = matchingExtensions.flatMap((facts) =>
      facts.codingKeyEnums.map((name) =>
        `extension ${facts.targetName}.${name}`
      )
    );
    if (
      matchingExtensions.some((facts) => facts.hasCustomDecoder) ||
      extensionCodingKeys.length > 0
    ) {
      structs.set(fullName, {
        ...candidate,
        hasCustomDecoder: candidate.hasCustomDecoder ||
          matchingExtensions.some((facts) => facts.hasCustomDecoder),
        unsupportedCodingKeyEnums: [
          ...candidate.unsupportedCodingKeyEnums,
          ...extensionCodingKeys,
        ].sort(),
      });
    }
  }
  const root = structs.get(SWIFT_RESPONSE_STRUCT);
  if (!root) {
    throw new ContractValidationError(
      `Swift response struct '${SWIFT_RESPONSE_STRUCT}' was not found.`,
    );
  }
  return {
    root,
    structs,
    propertyPaths: collectSwiftPropertyPaths(root, structs),
  };
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
  for (const exception of policy.intentionallyServerOnlyProperties) {
    if (!schema.topLevelProperties.has(exception)) {
      failures.push(
        `server-only schema exception '${exception}' is stale or misspelled`,
      );
    }
  }
  return failures;
}

function swiftTypeDescription(type: SwiftType): string {
  let value: string;
  if (type.kind === "array") {
    value = `[${swiftTypeDescription(type.element)}]`;
  } else if (type.kind === "dictionary") {
    value = `[${swiftTypeDescription(type.key)}: ${
      swiftTypeDescription(type.value)
    }]`;
  } else {
    value = type.name;
  }
  return `${value}${type.optional ? "?" : ""}`;
}

const safeSwiftIntegerRanges = new Map<
  string,
  readonly [minimum: number, maximum: number]
>([
  ["Int", [Number.MIN_SAFE_INTEGER, Number.MAX_SAFE_INTEGER]],
  ["Int8", [-128, 127]],
  ["Int16", [-32_768, 32_767]],
  ["Int32", [-2_147_483_648, 2_147_483_647]],
  ["Int64", [Number.MIN_SAFE_INTEGER, Number.MAX_SAFE_INTEGER]],
  ["UInt", [0, Number.MAX_SAFE_INTEGER]],
  ["UInt8", [0, 255]],
  ["UInt16", [0, 65_535]],
  ["UInt32", [0, 4_294_967_295]],
  ["UInt64", [0, Number.MAX_SAFE_INTEGER]],
]);

function compatiblePrimitive(
  node: SchemaNode,
  swiftType: SwiftType,
): boolean {
  if (swiftType.kind !== "named") return false;
  switch (node.kind) {
    case "boolean":
      return swiftType.name === "Bool";
    case "integer": {
      if (node.minimum === undefined || node.maximum === undefined) {
        return false;
      }
      const range = safeSwiftIntegerRanges.get(swiftType.name);
      return range !== undefined &&
        node.minimum >= range[0] &&
        node.maximum <= range[1];
    }
    case "number":
      // Edge JSON numbers are represented as IEEE-754 doubles. Wire DTOs use
      // Double so the validator never silently accepts a narrower Float or a
      // differently encoded Decimal/CGFloat boundary.
      return swiftType.name === "Double";
    case "string":
      return swiftType.name === "String";
    default:
      return false;
  }
}

function propertyForJSONName(
  owner: SwiftStruct,
  jsonName: string,
): SwiftProperty | undefined {
  const matches = [...owner.properties.values()].filter((property) =>
    property.jsonNames.has(jsonName)
  );
  if (matches.length > 1) {
    throw new ContractValidationError(
      `Swift DTO '${owner.fullName}' maps multiple properties to JSON key '${jsonName}'.`,
    );
  }
  return matches[0];
}

function validateStructuralContract(
  schema: SchemaContract,
  swift: SwiftContract,
  policy: ContractValidationPolicy,
): readonly string[] {
  const failures: string[] = [];
  const validatedPaths = new Set<string>();
  const usedServerAddedSwiftPaths = new Set<string>();
  const validatingObjects = new Set<string>();

  const validateNode = (
    node: SchemaNode,
    swiftType: SwiftType,
    owner: SwiftStruct,
  ): void => {
    validatedPaths.add(node.path);
    if (!swiftType.optional && (!node.required || node.nullable)) {
      failures.push(
        `schema '${node.path}' may be ${
          !node.required ? "absent" : "null"
        }, but Swift '${owner.fullName}' requires non-optional '${
          swiftTypeDescription(swiftType)
        }'`,
      );
    }

    if (node.kind === "array") {
      if (swiftType.kind !== "array") {
        failures.push(
          `schema '${node.path}' is an array, but Swift uses '${
            swiftTypeDescription(swiftType)
          }'`,
        );
        return;
      }
      if (!node.items) {
        failures.push(
          `schema '${node.path}' has no structurally resolved items`,
        );
        return;
      }
      validateNode(node.items, swiftType.element, owner);
      return;
    }

    if (node.kind === "object") {
      if (swiftType.kind !== "named") {
        failures.push(
          `schema '${node.path}' is an object, but Swift uses '${
            swiftTypeDescription(swiftType)
          }'`,
        );
        return;
      }
      const nested = resolveSwiftStruct(swiftType.name, owner, swift.structs);
      if (!nested) {
        failures.push(
          `schema '${node.path}' is an object, but Swift type '${swiftType.name}' could not be resolved to a DTO struct`,
        );
        return;
      }
      validateObject(node, nested);
      return;
    }

    if (!compatiblePrimitive(node, swiftType)) {
      const bounds = node.minimum !== undefined || node.maximum !== undefined
        ? ` with bounds ${node.minimum ?? "-∞"}...${node.maximum ?? "∞"}`
        : "";
      failures.push(
        `schema '${node.path}' is '${node.kind}'${bounds}, but Swift uses '${
          swiftTypeDescription(swiftType)
        }'`,
      );
    }
  };

  const validateObject = (
    objectNode: SchemaNode,
    owner: SwiftStruct,
  ): void => {
    if (owner.hasCustomDecoder) {
      failures.push(
        `Swift DTO '${owner.fullName}' has a custom init(from:), which the structural gate cannot prove safe`,
      );
      return;
    }
    if (owner.unsupportedCodingKeyEnums.length > 0) {
      failures.push(
        `Swift DTO '${owner.fullName}' declares unsupported CodingKey enum(s): ${
          owner.unsupportedCodingKeyEnums.join(", ")
        }`,
      );
      return;
    }
    const validationKey = `${objectNode.path}:${owner.fullName}`;
    if (validatingObjects.has(validationKey)) {
      failures.push(
        `recursive DTO graph '${validationKey}' is unsupported by the structural gate`,
      );
      return;
    }
    validatingObjects.add(validationKey);
    const matchedSwiftProperties = new Set<string>();

    for (const [jsonName, child] of objectNode.properties) {
      if (
        objectNode.path === "" &&
        policy.intentionallyServerOnlyProperties.has(jsonName)
      ) {
        continue;
      }
      const property = propertyForJSONName(owner, jsonName);
      if (!property) {
        failures.push(
          `schema '${child.path}' has no Swift property or CodingKey in '${owner.fullName}'`,
        );
        continue;
      }
      matchedSwiftProperties.add(property.name);
      validateNode(child, property.type, owner);
    }

    for (const property of owner.properties.values()) {
      if (matchedSwiftProperties.has(property.name)) continue;
      if (property.jsonNames.size === 0) {
        failures.push(
          `Swift '${owner.fullName}.${property.name}' has no synthesized CodingKey`,
        );
        continue;
      }
      const swiftPaths = [...property.jsonNames].map((jsonName) =>
        objectNode.path ? `${objectNode.path}.${jsonName}` : jsonName
      );
      if (
        swiftPaths.some((path) => {
          if (!policy.intentionallyServerAddedSwiftPaths.has(path)) {
            return false;
          }
          usedServerAddedSwiftPaths.add(path);
          return true;
        })
      ) {
        continue;
      }
      failures.push(
        `Swift '${owner.fullName}.${property.name}' ${
          property.type.optional
            ? "is absent from"
            : "is non-optional but has no field in"
        } schema object '${
          objectNode.path || "<root>"
        }' and is not an approved server-added path`,
      );
    }
    validatingObjects.delete(validationKey);
  };

  validateObject(schema.root, swift.root);
  for (const exception of policy.intentionallyServerAddedSwiftPaths) {
    if (!usedServerAddedSwiftPaths.has(exception)) {
      failures.push(
        `server-added Swift path exception '${exception}' is stale or misspelled`,
      );
    }
  }
  if (failures.length > 0) {
    throw new ContractValidationError(
      `Structural DTO compatibility validation failed:\n${
        failures.map((failure) => `- ${failure}`).join("\n")
      }`,
    );
  }
  return [...validatedPaths].filter(Boolean).sort();
}

export function validateContractSources(
  schemaSource: string,
  swiftSources: string | readonly string[],
  policy: ContractValidationPolicy = defaultValidationPolicy,
  schemaFileName = "schema.ts",
  swiftExtensionSources: string | readonly string[] = swiftSources,
): ContractValidationReport {
  const schemaContract = extractSchemaContract(
    schemaSource,
    schemaFileName,
  );
  const swiftContract = extractSwiftContract(
    swiftSources,
    swiftExtensionSources,
  );
  const swiftProperties = new Set(swiftContract.root.properties.keys());
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

  const validatedSchemaPaths = validateStructuralContract(
    schemaContract,
    swiftContract,
    policy,
  );

  return {
    schemaContract,
    swiftContract,
    swiftProperties,
    validatedSchemaPaths,
    intentionallyServerOnlyProperties: [...schemaContract.topLevelProperties]
      .filter((property) =>
        policy.intentionallyServerOnlyProperties.has(property)
      )
      .sort(),
    intentionallyServerAddedSwiftPaths: [
      ...policy.intentionallyServerAddedSwiftPaths,
    ].sort(),
    swiftExtensionSourceCount: typeof swiftExtensionSources === "string"
      ? 1
      : swiftExtensionSources.length,
  };
}

async function discoverSwiftSourcePaths(root: string): Promise<string[]> {
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
      // Symlinks are intentionally ignored so a source-tree scan cannot escape
      // its reviewed repository root.
    }
  };
  await visit(root);
  return paths;
}

export async function validateAPIContracts(
  paths: ContractPaths = {
    schemaPath: canonicalIdentifySchemaPath,
    swiftPaths: [inferenceEdgeDTOsPath],
    swiftExtensionSearchRoots: [iosApplicationSwiftRootPath],
  },
  policy: ContractValidationPolicy = defaultValidationPolicy,
): Promise<ContractValidationReport> {
  let schemaSource: string;
  let swiftSources: string[];
  let swiftExtensionSources: string[];
  try {
    const extensionPaths = [
      ...new Set(
        (
          await Promise.all(
            (paths.swiftExtensionSearchRoots ?? []).map(
              discoverSwiftSourcePaths,
            ),
          )
        ).flat(),
      ),
    ].sort();
    [schemaSource, swiftSources, swiftExtensionSources] = await Promise.all([
      Deno.readTextFile(paths.schemaPath),
      Promise.all(paths.swiftPaths.map((path) => Deno.readTextFile(path))),
      extensionPaths.length > 0
        ? Promise.all(
          extensionPaths.map((path) => Deno.readTextFile(path)),
        )
        : Promise.all(paths.swiftPaths.map((path) => Deno.readTextFile(path))),
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
    swiftSources,
    policy,
    paths.schemaPath,
    swiftExtensionSources,
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
      `${report.swiftProperties.size} Swift ${SWIFT_RESPONSE_STRUCT} properties; ` +
      `structurally validated ${report.validatedSchemaPaths.length} schema paths and ` +
      `scanned ${report.swiftExtensionSourceCount} Swift source files for extensions.`,
  );
  if (report.intentionallyServerOnlyProperties.length > 0) {
    console.log(
      `Explicit server-only fields: ${
        report.intentionallyServerOnlyProperties.join(", ")
      }.`,
    );
  }
  if (report.intentionallyServerAddedSwiftPaths.length > 0) {
    console.log(
      `Explicit server-added Swift paths: ${
        report.intentionallyServerAddedSwiftPaths.join(", ")
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
