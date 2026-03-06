import Foundation

/// Securely manages global iOS application bounds reading explicitly from configured Property Lists (.plist) or xcconfig parameters.
enum MerianEnvironment {
    enum Keys {
        static let geminiApiKey = "GEMINI_API_KEY"
        static let supabaseUrl = "SUPABASE_URL"
        static let supabaseAnonKey = "SUPABASE_ANON_KEY"
    }

    private static let infoDictionary: [String: Any] = {
        guard let dict = Bundle.main.infoDictionary else {
            return [:]
        }
        return dict
    }()

    static let geminiApiKey: String = {
        guard let key = MerianEnvironment.infoDictionary[Keys.geminiApiKey] as? String, !key.isEmpty else {
            print("⚠️ WARNING: GEMINI_API_KEY missing from Info.plist. Falling back to default proxy string.")
            return "YOUR_GEMINI_API_KEY"
        }
        return key
    }()

    static let supabaseUrl: String = {
        guard let urlString = MerianEnvironment.infoDictionary[Keys.supabaseUrl] as? String, !urlString.isEmpty else {
            print("⚠️ WARNING: SUPABASE_URL missing from Info.plist. Falling back to default proxy string.")
            return "YOUR_SUPABASE_URL"
        }
        return urlString
    }()

    static let supabaseAnonKey: String = {
        guard let key = MerianEnvironment.infoDictionary[Keys.supabaseAnonKey] as? String, !key.isEmpty else {
            print("⚠️ WARNING: SUPABASE_ANON_KEY missing from Info.plist. Falling back to default proxy string.")
            return "YOUR_SUPABASE_ANON_KEY"
        }
        return key
    }()
}
