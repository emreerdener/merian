# Core Intents

The `Intents` directory contains the App Intents infrastructure.

## Purpose
This area exposes the app's capabilities to Siri and the iOS Shortcuts app. It defines the structured intents that allow users to trigger actions (like initiating a capture or viewing a specific collection) from outside the app via voice or automation.

## Routing contract

`IdentifyNatureIntent` and `RecallLastFindIntent` submit `.identifyNature` and
`.recallLastFind` through the DI-owned `AppRouteCoordinator` with source
`.appIntent`. They do not publish `AppEvent`, post a NotificationCenter message,
or present SwiftUI directly. Capture claims the request after startup and only
applies it when the shared UIKit presentation slot is available.

App-intent envelopes are process-local, priority 300 requests with a two-minute
delivery lifetime. They survive an ordinary session-generation reset, while
account-sensitive targets are still fenced on an account transition. An
unavailable last scan is rejected terminally so it cannot stall later routes.
The complete ordering and durability rules are in
[Event and Presentation Routing](../../../../../docs/system-architecture/10-event-and-presentation-routing.md).
