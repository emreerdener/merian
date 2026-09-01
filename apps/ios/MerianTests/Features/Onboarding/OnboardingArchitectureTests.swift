@testable import Merian
import Foundation
import Testing

@Suite("Onboarding architecture")
struct OnboardingArchitectureTests {
    @Test func ownershipDirectoriesRemainExplicit() throws {
        let root = try onboardingSourceRoot()
        for relativePath in [
            "Shell/Components",
            "Shell/Services",
            "Shell/ViewModels",
            "Shell/Views",
            "Permissions/Location",
            "Permissions/Services",
            "Steps/Models",
            "Steps/Ready/Components",
            "Steps/Ready/Models",
            "Steps/Ready/ViewModels",
            "Steps/Shared/Components"
        ] {
            var isDirectory: ObjCBool = false
            let directory = root.appendingPathComponent(relativePath)
            #expect(FileManager.default.fileExists(
                atPath: directory.path,
                isDirectory: &isDirectory
            ))
            #expect(isDirectory.boolValue)
        }
    }

    @Test func productionFilesRemainWithinLineCeiling() throws {
        for file in try swiftFiles(in: onboardingSourceRoot()) {
            let lineCount = try contents(of: file)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(
                lineCount <= 600,
                "\(file.lastPathComponent) has \(lineCount) lines"
            )
        }
    }

    @Test func liveEffectsRemainInServicesAndPermissionAdapters() throws {
        let root = try onboardingSourceRoot()
        let forbiddenTokens = [
            "AppSettings.shared",
            "AppTelemetry.trackOnboardingCompleted",
            "AVCaptureDevice.requestAccess",
            "ConsentManager.shared",
            "HardwareOrchestrator.shared",
            "OfflineQueueManager.shared"
        ]

        for file in try swiftFiles(in: root) {
            let relativePath = file.path.replacingOccurrences(
                of: root.path + "/",
                with: ""
            )
            let isAllowedOwner = relativePath.contains("/Services/")
                || relativePath.hasPrefix("Permissions/Location/")
            guard !isAllowedOwner else { continue }

            let source = try contents(of: file)
            for token in forbiddenTokens {
                #expect(
                    !source.contains(token),
                    "\(relativePath) resolves \(token)"
                )
            }
        }
    }

    @Test func stepViewsDoNotImportNativePermissionFrameworks() throws {
        let steps = try onboardingSourceRoot().appendingPathComponent("Steps")
        for file in try swiftFiles(in: steps) {
            let source = try contents(of: file)
            for token in [
                "import AVFoundation",
                "import CoreLocation",
                "AVCaptureDevice",
                "CLLocationManager"
            ] {
                #expect(
                    !source.contains(token),
                    "\(file.lastPathComponent) owns native permission work"
                )
            }
        }
    }

    @Test func locationAuthorizationIsReadAfterTheMainActorHop() throws {
        let source = try contents(
            of: try onboardingSourceRoot().appendingPathComponent(
                "Permissions/Location/LocationPermissionDelegate.swift"
            )
        )
        let callbackRange = try #require(source.range(
            of: "nonisolated func locationManagerDidChangeAuthorization"
        ))
        let callbackSource = source[callbackRange.lowerBound...]
        let mainActorRange = try #require(callbackSource.range(
            of: "Task { @MainActor"
        ))
        let authorizationReadRange = try #require(callbackSource.range(
            of: "locationManager.authorizationStatus"
        ))

        #expect(mainActorRange.lowerBound < authorizationReadRange.lowerBound)
    }

    @Test func deterministicModelsRemainPlatformNeutral() throws {
        let modelRoots = [
            try onboardingSourceRoot().appendingPathComponent("Steps/Models"),
            try onboardingSourceRoot().appendingPathComponent(
                "Steps/Ready/Models"
            )
        ]

        for modelRoot in modelRoots {
            for file in try swiftFiles(in: modelRoot) {
                let source = try contents(of: file)
                for forbiddenImport in [
                    "import AVFoundation",
                    "import CoreLocation",
                    "import SwiftUI",
                    "import UIKit"
                ] {
                    #expect(
                        !source.contains(forbiddenImport),
                        "\(file.lastPathComponent) imports a platform layer"
                    )
                }
            }
        }
    }

    @Test func appRootInjectsTheSelectedManagerInstances() throws {
        let appSource = try contents(
            of: try repositoryRoot().appendingPathComponent(
                "apps/ios/Merian/App/MerianApp.swift"
            )
        )

        #expect(appSource.contains("OnboardingView("))
        #expect(appSource.contains("appSettings: appSettings"))
        #expect(appSource.contains("consentManager: consentManager"))
        #expect(appSource.contains("offlineQueueManager:"))
        #expect(appSource.contains("diContainer.offlineQueueManager"))
        #expect(appSource.contains("hardwareOrchestrator:"))
        #expect(appSource.contains("diContainer.hardwareOrchestrator"))
    }

    private func onboardingSourceRoot() throws -> URL {
        let root = try repositoryRoot().appendingPathComponent(
            "apps/ios/Merian/Features/Onboarding"
        )
        #expect(FileManager.default.fileExists(atPath: root.path))
        return root
    }

    private func repositoryRoot() throws -> URL {
        var candidate = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
        for _ in 0..<12 {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("project.yml").path
            ) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func contents(of file: URL) throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }

    private func swiftFiles(in root: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else { return [] }

        return try enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "swift",
                  try url.resourceValues(forKeys: keys).isRegularFile == true
            else { return nil }
            return url
        }
    }
}
