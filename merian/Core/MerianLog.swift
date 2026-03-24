import os

enum MerianLog {
    static let auth = Logger(subsystem: "com.merian.app", category: "Auth")
    static let network = Logger(subsystem: "com.merian.app", category: "Network")
    static let data = Logger(subsystem: "com.merian.app", category: "Data")
    static let hardware = Logger(subsystem: "com.merian.app", category: "Hardware")
    static let general = Logger(subsystem: "com.merian.app", category: "General")
}
