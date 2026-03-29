# Sync Collections

The central reconciliation endpoint strictly for Offline-First Data.
If the iOS app goes offline to scan deep in the woods, the database states diverge. Upon re-connection, the SwiftData infrastructure calls this endpoint to merge local offline scans, resolve timestamp conflicts, and securely re-align the server with the mobile app's reality.
