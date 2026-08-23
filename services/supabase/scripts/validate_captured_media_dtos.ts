/**
 * Captured-media wire-contract validator and Swift DTO generator.
 *
 * This boundary is intentionally separate from Identify's provider/response
 * contract generator: `captured_media` is a durable JSONB outer-key union, not
 * a Gemini response object. Both generators still run from the same CI gate.
 */

import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import {
  CAPTURED_MEDIA_WIRE_VERSION,
  capturedMediaSwiftDTOContract,
} from "../functions/_shared/capturedMediaContract.ts";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
export const repositoryRoot = resolve(scriptDirectory, "../../..");
export const canonicalCapturedMediaContractPath = resolve(
  repositoryRoot,
  "services/supabase/functions/_shared/capturedMediaContract.ts",
);
export const canonicalCapturedMediaSwiftDTOPath = resolve(
  repositoryRoot,
  "apps/ios/Merian/Core/Data/Database/CapturedMediaWireDTOs.swift",
);
export const iosSourceGraphRoot = resolve(repositoryRoot, "apps/ios");

export const GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN =
  "// BEGIN GENERATED: CapturedMedia wire DTOs";
export const GENERATED_CAPTURED_MEDIA_SWIFT_END =
  "// END GENERATED: CapturedMedia wire DTOs";

export const GENERATED_CAPTURED_MEDIA_TYPE_NAMES = [
  "CapturedMediaWireStorageDTO",
  "CapturedMediaStoredReferenceDTO",
  "CapturedMediaVideoReferenceDTO",
  "CapturedMediaDescriptionDTO",
  "CapturedMediaWireItemDTO",
  "CapturedMediaWireManifestDTO",
] as const;

export class CapturedMediaDTOValidationError extends Error {
  override readonly name = "CapturedMediaDTOValidationError";
}

function swiftVariantPayloadType(payload: string): string {
  switch (payload) {
    case "reference":
      return "CapturedMediaStoredReferenceDTO";
    case "video":
      return "CapturedMediaVideoReferenceDTO";
    case "description":
      return "CapturedMediaDescriptionDTO";
    default:
      throw new CapturedMediaDTOValidationError(
        `Unsupported captured-media payload kind '${payload}'.`,
      );
  }
}

function renderVariantCases(): string {
  return capturedMediaSwiftDTOContract.variants
    .map((variant) =>
      `    case ${variant.swiftCase}(${
        swiftVariantPayloadType(variant.payload)
      })`
    )
    .join("\n");
}

function renderVariantSwitch(): string {
  return capturedMediaSwiftDTOContract.variants
    .map((variant) => {
      const type = swiftVariantPayloadType(variant.payload);
      return [
        `        case "${variant.wireKey}":`,
        `            self = .${variant.swiftCase}(`,
        `                try container.decode(`,
        `                    CapturedMediaWirePayloadEnvelope<${type}>.self,`,
        `                    forKey: key`,
        `                ).value`,
        `            )`,
      ].join("\n");
    })
    .join("\n");
}

function renderKnownVariantKeys(): string {
  return capturedMediaSwiftDTOContract.variants
    .map((variant) => `"${variant.wireKey}"`)
    .join(", ");
}

export function renderGeneratedCapturedMediaSwiftDTOBlock(): string {
  if (capturedMediaSwiftDTOContract.version !== CAPTURED_MEDIA_WIRE_VERSION) {
    throw new CapturedMediaDTOValidationError(
      "Captured-media Swift metadata version drifted from the runtime contract.",
    );
  }
  const storageValue = capturedMediaSwiftDTOContract.storageValues[0];
  if (
    capturedMediaSwiftDTOContract.storageValues.length !== 1 ||
    storageValue !== "remoteURL"
  ) {
    throw new CapturedMediaDTOValidationError(
      "Captured-media V1 must generate exactly the remoteURL storage case.",
    );
  }
  if (
    !capturedMediaSwiftDTOContract.legacyReadCompatibility
      .localFileReferenceIgnored
  ) {
    throw new CapturedMediaDTOValidationError(
      "Captured-media compatibility must explicitly ignore legacy localFile references.",
    );
  }

  return `${GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN}
// Generated from services/supabase/functions/_shared/capturedMediaContract.ts.
// Do not edit this block by hand; run make generate-captured-media-dto-contract.

private struct CapturedMediaWireCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == CapturedMediaWireCodingKey {
    func requireAllowedKeys(_ allowed: Set<String>, path: String) throws {
        if let unexpected = allKeys.map(\\.stringValue).first(where: { !allowed.contains($0) }) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "\\(path) contains unexpected key '\\(unexpected)'."
            ))
        }
    }
}

private struct CapturedMediaWirePayloadEnvelope<Value: Decodable>: Decodable {
    let value: Value

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(["_0"], path: "captured_media payload")
        guard let key = CapturedMediaWireCodingKey(stringValue: "_0"), container.contains(key) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media payload is missing _0."
            ))
        }
        value = try container.decode(Value.self, forKey: key)
    }
}

enum CapturedMediaWireStorageDTO: String, Decodable, Sendable {
    case ${storageValue}
    case localFile
}

struct CapturedMediaStoredReferenceDTO: Decodable, Sendable {
    let storage: CapturedMediaWireStorageDTO
    let path: String
    let sourceIndex: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(
            ["storage", "path", "sourceIndex", "source_index"],
            path: "captured_media reference"
        )
        let storageKey = CapturedMediaWireCodingKey(stringValue: "storage")!
        let pathKey = CapturedMediaWireCodingKey(stringValue: "path")!
        let sourceIndexKey = CapturedMediaWireCodingKey(stringValue: "sourceIndex")!
        let sourceIndexSnakeKey = CapturedMediaWireCodingKey(stringValue: "source_index")!
        guard !(container.contains(sourceIndexKey) && container.contains(sourceIndexSnakeKey)) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media reference contains both source-index aliases."
            ))
        }

        storage = try container.decode(CapturedMediaWireStorageDTO.self, forKey: storageKey)
        let decodedPath = try container.decode(String.self, forKey: pathKey)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !decodedPath.isEmpty,
              decodedPath.count <= ${capturedMediaSwiftDTOContract.maxPathLength} else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media reference path is outside the V1 bound."
            ))
        }
        if storage == .remoteURL {
            guard let components = URLComponents(string: decodedPath),
                  components.scheme?.lowercased() == "https",
                  components.host?.isEmpty == false,
                  components.user == nil,
                  components.password == nil else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "captured_media remote reference must use a credential-free HTTPS URL."
                ))
            }
        }
        path = decodedPath

        let decodedSourceIndex = try container.decodeIfPresent(Int.self, forKey: sourceIndexKey)
            ?? container.decodeIfPresent(Int.self, forKey: sourceIndexSnakeKey)
        if let decodedSourceIndex,
           !(0...${capturedMediaSwiftDTOContract.maxSourceIndex}).contains(decodedSourceIndex) {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media sourceIndex is outside the V1 bound."
            ))
        }
        sourceIndex = decodedSourceIndex
    }
}

struct CapturedMediaVideoReferenceDTO: Decodable, Sendable {
    let video: CapturedMediaStoredReferenceDTO
    let thumbnail: CapturedMediaStoredReferenceDTO?
    let audio: CapturedMediaStoredReferenceDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(
            ["video", "thumbnail", "audio"],
            path: "captured_media video"
        )
        video = try container.decode(
            CapturedMediaStoredReferenceDTO.self,
            forKey: CapturedMediaWireCodingKey(stringValue: "video")!
        )
        thumbnail = try container.decodeIfPresent(
            CapturedMediaStoredReferenceDTO.self,
            forKey: CapturedMediaWireCodingKey(stringValue: "thumbnail")!
        )
        audio = try container.decodeIfPresent(
            CapturedMediaStoredReferenceDTO.self,
            forKey: CapturedMediaWireCodingKey(stringValue: "audio")!
        )
    }
}

struct CapturedMediaDescriptionDTO: Decodable, Sendable {
    let freeText: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        try container.requireAllowedKeys(
            ["freeText", "free_text", "addedAt", "added_at"],
            path: "captured_media description"
        )
        let freeTextKey = CapturedMediaWireCodingKey(stringValue: "freeText")!
        let freeTextSnakeKey = CapturedMediaWireCodingKey(stringValue: "free_text")!
        guard !(container.contains(freeTextKey) && container.contains(freeTextSnakeKey)) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media description contains both free-text aliases."
            ))
        }
        let decodedText: String
        if container.contains(freeTextKey) {
            decodedText = try container.decode(String.self, forKey: freeTextKey)
        } else {
            decodedText = try container.decode(String.self, forKey: freeTextSnakeKey)
        }
        let normalizedText = decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              normalizedText.count <= ${capturedMediaSwiftDTOContract.maxDescriptionLength} else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media description text is outside the V1 bound."
            ))
        }
        freeText = normalizedText
        // Legacy addedAt/added_at values are intentionally ignored without decoding.
        // Completed ordering is owned by manifest array order, not this retired field.
    }
}

enum CapturedMediaWireItemDTO: Decodable, Sendable {
${renderVariantCases()}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CapturedMediaWireCodingKey.self)
        let keys = container.allKeys
        guard keys.count == 1, let key = keys.first,
              [${renderKnownVariantKeys()}].contains(key.stringValue) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media item must contain exactly one known variant."
            ))
        }
        switch key.stringValue {
${renderVariantSwitch()}
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "captured_media item contains an unknown variant."
            ))
        }
    }
}

struct CapturedMediaWireManifestDTO: Decodable, Sendable {
    let items: [CapturedMediaWireItemDTO]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var decodedItems: [CapturedMediaWireItemDTO] = []
        decodedItems.reserveCapacity(min(container.count ?? 0, ${capturedMediaSwiftDTOContract.maxItems}))
        while !container.isAtEnd {
            guard decodedItems.count < ${capturedMediaSwiftDTOContract.maxItems} else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "captured_media exceeds the V1 item bound."
                ))
            }
            decodedItems.append(try container.decode(CapturedMediaWireItemDTO.self))
        }
        // Legacy rows may contain an empty array instead of SQL null. Treat it
        // as a missing manifest so compatibility URL/context columns can hydrate.
        items = decodedItems
    }
}
${GENERATED_CAPTURED_MEDIA_SWIFT_END}`;
}

export function validateGeneratedCapturedMediaSwiftSource(
  source: string,
): void {
  const expected = renderGeneratedCapturedMediaSwiftDTOBlock();
  const begin = source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN);
  const endMarker = source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_END);
  if (begin < 0 || endMarker < begin) {
    throw new CapturedMediaDTOValidationError(
      "CapturedMediaWireDTOs.swift is missing generated markers.",
    );
  }
  if (
    source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN, begin + 1) >= 0 ||
    source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_END, endMarker + 1) >= 0
  ) {
    throw new CapturedMediaDTOValidationError(
      "CapturedMediaWireDTOs.swift contains duplicate generated markers.",
    );
  }
  const end = endMarker + GENERATED_CAPTURED_MEDIA_SWIFT_END.length;
  const actual = source.slice(begin, end).replaceAll("\r\n", "\n");
  if (actual !== expected) {
    throw new CapturedMediaDTOValidationError(
      "Generated captured-media Swift DTOs are stale.",
    );
  }
}

export function replaceGeneratedCapturedMediaSwiftDTOBlock(
  source: string,
): string {
  const begin = source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN);
  const endMarker = source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_END);
  if (begin < 0 || endMarker < begin) {
    throw new CapturedMediaDTOValidationError(
      "CapturedMediaWireDTOs.swift is missing generated markers.",
    );
  }
  const end = endMarker + GENERATED_CAPTURED_MEDIA_SWIFT_END.length;
  return `${
    source.slice(0, begin)
  }${renderGeneratedCapturedMediaSwiftDTOBlock()}${source.slice(end)}`;
}

async function discoverSwiftSourcePaths(root: string): Promise<string[]> {
  const paths: string[] = [];
  async function visit(directory: string): Promise<void> {
    for await (const entry of Deno.readDir(directory)) {
      const path = resolve(directory, entry.name);
      if (entry.isDirectory) {
        await visit(path);
      } else if (entry.isFile && entry.name.endsWith(".swift")) {
        paths.push(path);
      }
    }
  }
  await visit(root);
  return paths.sort();
}

function sourceOutsideGeneratedBlock(source: string): string {
  const begin = source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_BEGIN);
  const endMarker = source.indexOf(GENERATED_CAPTURED_MEDIA_SWIFT_END);
  if (begin < 0 || endMarker < begin) return source;
  const end = endMarker + GENERATED_CAPTURED_MEDIA_SWIFT_END.length;
  return `${source.slice(0, begin)}\n${source.slice(end)}`;
}

function escapeRegularExpression(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export async function validateCapturedMediaDTOContract(): Promise<{
  readonly swiftSourceCount: number;
  readonly generatedTypeCount: number;
}> {
  const canonicalSource = await Deno.readTextFile(
    canonicalCapturedMediaSwiftDTOPath,
  );
  validateGeneratedCapturedMediaSwiftSource(canonicalSource);
  const swiftPaths = await discoverSwiftSourcePaths(iosSourceGraphRoot);
  if (!swiftPaths.includes(canonicalCapturedMediaSwiftDTOPath)) {
    throw new CapturedMediaDTOValidationError(
      "Complete iOS source scan omitted CapturedMediaWireDTOs.swift.",
    );
  }

  for (const typeName of GENERATED_CAPTURED_MEDIA_TYPE_NAMES) {
    const declaration = new RegExp(
      `\\b(?:struct|enum|typealias)\\s+${escapeRegularExpression(typeName)}\\b`,
      "g",
    );
    let declarationCount = 0;
    for (const path of swiftPaths) {
      const source = await Deno.readTextFile(path);
      const inspected = path === canonicalCapturedMediaSwiftDTOPath
        ? sourceOutsideGeneratedBlock(source)
        : source;
      declarationCount += [...inspected.matchAll(declaration)].length;
    }
    if (declarationCount > 0) {
      throw new CapturedMediaDTOValidationError(
        `Generated DTO '${typeName}' is redeclared outside its generated block.`,
      );
    }
  }

  const requiredRoot = resolve(repositoryRoot, "apps/ios/Merian");
  const requiredPrefix = `${requiredRoot}${sep}`;
  if (
    !swiftPaths.some((path) =>
      path === requiredRoot || path.startsWith(requiredPrefix)
    )
  ) {
    throw new CapturedMediaDTOValidationError(
      "Complete iOS source scan omitted the Merian production source root.",
    );
  }
  return {
    swiftSourceCount: swiftPaths.length,
    generatedTypeCount: GENERATED_CAPTURED_MEDIA_TYPE_NAMES.length,
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
    throw new CapturedMediaDTOValidationError(
      `Unknown argument(s): ${unknownArguments.join(", ")}.`,
    );
  }
  if (Deno.args.includes("--write-swift")) {
    const source = await Deno.readTextFile(canonicalCapturedMediaSwiftDTOPath);
    await Deno.writeTextFile(
      canonicalCapturedMediaSwiftDTOPath,
      replaceGeneratedCapturedMediaSwiftDTOBlock(source),
    );
    console.log(
      `Regenerated ${displayPath(canonicalCapturedMediaSwiftDTOPath)}.`,
    );
  }

  console.log("Starting captured-media wire-contract validation.");
  console.log(`Contract: ${displayPath(canonicalCapturedMediaContractPath)}`);
  console.log(`Swift:    ${displayPath(canonicalCapturedMediaSwiftDTOPath)}`);
  const report = await validateCapturedMediaDTOContract();
  console.log(
    `Validated ${report.generatedTypeCount} generated captured-media DTOs across ${report.swiftSourceCount} Swift source files.`,
  );
}

if (import.meta.main) {
  try {
    await main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  }
}
