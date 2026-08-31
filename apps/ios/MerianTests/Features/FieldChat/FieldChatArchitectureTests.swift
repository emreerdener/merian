import Foundation
import Testing

@testable import Merian

struct FieldChatArchitectureTests {
    @Test func fieldChatHasCrossFeatureOwnershipAndBoundedProductionFiles() throws {
        let repositoryRoot = try repositoryRoot()
        let fieldChatRoot = repositoryRoot.appendingPathComponent(
            "apps/ios/Merian/Features/FieldChat"
        )
        let oldOwner = repositoryRoot.appendingPathComponent(
            "apps/ios/Merian/Features/Insights/Chat"
        )
        #expect(FileManager.default.fileExists(atPath: fieldChatRoot.path))
        #expect(!FileManager.default.fileExists(atPath: oldOwner.path))

        let swiftFiles = try swiftFiles(under: fieldChatRoot)
        #expect(!swiftFiles.isEmpty)
        for file in swiftFiles {
            let lineCount = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 600, "\(file.lastPathComponent) has \(lineCount) lines")
        }
    }

    @Test func liveResolutionIsServicesOnly() throws {
        let repositoryRoot = try repositoryRoot()
        let fieldChatRoot = repositoryRoot.appendingPathComponent(
            "apps/ios/Merian/Features/FieldChat"
        )
        let forbidden = [
            "MerianNetworkClient.shared",
            "HapticManager.shared",
            "PostHogManager.shared",
            "UIPasteboard.general",
            "AppTelemetry.trackSpeciesDictionaryFieldChatAction"
        ]

        for file in try swiftFiles(under: fieldChatRoot) {
            guard !file.path.contains("/Services/") else { continue }
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in forbidden {
                #expect(!source.contains(token), "\(file.lastPathComponent) resolves \(token)")
            }
        }
    }

    @Test func modelsRemainPlatformNeutral() throws {
        let modelsRoot = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/FieldChat/Models"
        )
        for file in try swiftFiles(under: modelsRoot) {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("import SwiftUI"))
            #expect(!source.contains("import UIKit"))
            #expect(!source.contains("MerianNetworkClient"))
        }
    }

    @Test func viewsAndComponentsDoNotOwnNetworking() throws {
        let fieldChatRoot = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/FieldChat"
        )
        let forbidden = [
            "MerianNetworkClient",
            "URLSession",
            "Supabase",
            "dependencies.endpoint"
        ]

        for owner in ["Views", "Components"] {
            let root = fieldChatRoot.appendingPathComponent(owner)
            for file in try swiftFiles(under: root) {
                let source = try String(contentsOf: file, encoding: .utf8)
                for token in forbidden {
                    #expect(!source.contains(token), "\(file.lastPathComponent) owns \(token)")
                }
            }
        }
    }

    private func repositoryRoot() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            root.deleteLastPathComponent()
        }
        return root
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys
        ) else {
            return []
        }
        return try enumerator.compactMap { value -> URL? in
            guard let url = value as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: Set(keys)).isRegularFile == true else {
                return nil
            }
            return url
        }
    }
}
