import Foundation

enum MerianEnvironment {
    private enum Keys {
        static let geminiApiKey = "AIzaSyAbez7rtSTKb-mdBO1PmZpQLTo7vfd9eFc"
        static let supabaseUrl = "https://qlarqavoqhkuwzmevrmf.supabase.co"
        static let supabaseAnonKey = "sb_publishable_ASBlNxWdEMTI8YeimWZ0-Q_-mLguhWk"
        static let revenueCatApiKey = "test_GmepIVyBRbvnwdickopfprfCGjq"
        static let postHogApiKey = "phc_o3CtiYQn5pUy50wCSjfRHiE89jQMc0qS9QFybEksdhn"
        static let telemetryAppID = "A316F801-4566-4F85-AF50-F23E31EC9BBD"
    }

    static let geminiApiKey: String = Keys.geminiApiKey
    static let supabaseUrl: String = Keys.supabaseUrl
    static let supabaseAnonKey: String = Keys.supabaseAnonKey
    static let revenueCatApiKey: String = Keys.revenueCatApiKey
    static let postHogApiKey: String = Keys.postHogApiKey
    static let telemetryAppID: String = Keys.telemetryAppID
}