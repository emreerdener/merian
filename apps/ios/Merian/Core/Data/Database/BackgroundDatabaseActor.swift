import SwiftData

/// Swift 6-safe actor that owns background SwiftData reads and writes.
///
/// Focused sibling extensions organize each persistence workflow. Values that
/// require response decoding, filesystem access, or main-actor side effects are
/// prepared by services before they cross this boundary.
@ModelActor
actor BackgroundDatabaseActor {}
