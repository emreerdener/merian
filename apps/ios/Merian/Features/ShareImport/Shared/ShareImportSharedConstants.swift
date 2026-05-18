import CoreGraphics
import Foundation

enum ShareImportSharedConstants {
    static let appGroupIdentifier = "group.app.merian.shared"
    static let keychainAccessGroupSuffix = "app.merian.shared"
    static let appIdentifierPrefixInfoKey = "MERIAN_APP_IDENTIFIER_PREFIX"
    static let supabaseKeychainService = "supabase.gotrue.swift"

    static let settingsDefaultsKey = "share-import-settings-snapshot"
    static let receiptsFilename = "share-import-receipts.json"

    static let imageMaxDimension: CGFloat = 1_024
    static let imageCompressionQuality = 0.85
    static let authExpiryRefreshMargin: TimeInterval = 30
}
