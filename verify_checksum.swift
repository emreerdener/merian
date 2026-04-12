import Foundation
import SwiftData
@testable import Merian

@MainActor
func check() throws {
    let s33 = Schema(versionedSchema: MerianSchemaV33.self)
    let s34 = Schema(versionedSchema: MerianSchemaV34.self)
    let s35 = Schema(versionedSchema: MerianSchemaV35.self)
    let s36 = Schema(versionedSchema: MerianSchemaV36.self)

    let encoder = JSONEncoder()
    print("V33 equals V34?", s33.versionChecksum == s34.versionChecksum)
    print("V34 equals V35?", s34.versionChecksum == s35.versionChecksum)
    print("V35 equals V36?", s35.versionChecksum == s36.versionChecksum)
}

try check()
