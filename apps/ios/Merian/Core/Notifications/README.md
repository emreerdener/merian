# Core Notifications

`Core/Notifications` owns the app-wide iOS notification boundary: system
authorization, APNs registration, local notification scheduling and routing, and
the aggregate app-icon badge. It is separate from
`Features/Explore/Notifications`, which owns the visible in-app activity feed,
reply-thread presentation, pagination, and mark-read interaction state.

## Ownership

- `PushNotificationManager.swift` is the caller-compatible `@MainActor` facade
  and `UNUserNotificationCenterDelegate`. It projects permission state, accepts
  APNs callbacks, schedules typed descriptors, and emits validated `AppRoute`
  values through its injected route closure.
- `AppIconBadgeCoordinator.swift` is the source-compatible static facade used by
  lifecycle and feature callers. It delegates state to
  `Badges/AppIconBadgeController.swift`.
- `Models/` contains immutable registration and local-notification values. The
  registration snapshot's account scope participates only in local coalescing
  and is never part of the endpoint payload.
- `Policies/` contains deterministic token encoding, payload routing,
  foreground-presentation, local descriptor, badge normalization, aggregation,
  and refresh-reuse decisions.
- `Coordination/PushRegistrationCoordinator.swift` serializes remote
  registration. It retains the newest settings/token snapshot that arrives while
  a request is suspended, coalesces an equal trailing snapshot after success,
  and retries an equal trailing snapshot after failure.
- `Services/SystemNotificationCenterService.swift` is the sole owner of
  `UNUserNotificationCenter.current()` and notification-related `UIApplication`
  effects.
- `Services/PushNotificationPreferencesStore.swift` is the low-level defaults
  bridge for permission, APNs token, remote preferences, and synchronous
  inference-banner suppression.
- `Services/PushRegistrationService.swift` is the sole push-registration
  endpoint adapter.
- `Services/PushRegistrationContextService.swift` projects the current
  authenticated account solely for account-aware registration coalescing.
- `Services/AppIconBadgeDependencies.swift` composes persisted unread state,
  unseen-scan state, OS badge presentation, time, diagnostics, and the unread
  count endpoint for the badge controller.

No view or feature state owner should call `UNUserNotificationCenter`,
`UIApplication` notification APIs, Supabase session state, or push/badge
endpoints directly. New live effects belong in a focused service closure, not in
either compatibility facade. Do not introduce a notification singleton beyond
the two existing source-compatible facades.

## Behavioral and concurrency contracts

- System categories, visible copy, identifiers, thread grouping, time-sensitive
  delivery, attachment behavior, and typed route payloads remain stable.
- Explore activity remains visible in the foreground. Achievement notifications
  and inference notifications presented over an active Insight surface remain
  silent.
- An inference scan ID becomes deduplicated only after
  `UNUserNotificationCenter` accepts its request. A failed add removes the
  pending ID so a later call can retry; simultaneous calls still coalesce.
- Permission reads use a generation and cancel replacement work, so an older
  response cannot overwrite newer state. A native authorization prompt
  invalidates an admitted read and temporarily defers new polling; its final
  user decision therefore remains authoritative. Its completion returns before
  remote preference synchronization, so network latency cannot hold the
  permission sheet open; the coordinator still drains the resulting snapshot.
- Remote registration drains the latest admitted snapshot. A token or preference
  change that arrives during an active request is never silently discarded. The
  snapshot includes a non-wire account scope, so an otherwise-identical
  registration for a replacement account cannot coalesce behind the prior
  account's authenticated call.
- Badge refresh callers share one active task. A successful count is reusable
  for ten seconds; failure or cancellation does not start that window or erase
  the last count. A local count mutation, including notification-sheet
  mark-read, cancels older refresh work and advances the state generation.
  Accepted account cleanup applies the same fence and clears the reuse window,
  so even a cancellation-ignoring loader cannot restore stale state. A backward
  wall-clock adjustment invalidates reuse, and aggregate addition saturates
  instead of overflowing.
- The OS badge is the sum of the normalized Explore unread count and one when a
  completed scan is unseen.

## Verification

Mirrored deterministic tests live in `MerianTests/Core/Notifications/`:

- `PushNotificationPolicyTests` locks token, registration, routing,
  presentation, copy, and descriptor contracts.
- `PushRegistrationCoordinatorTests` covers changed/latest/equal overlapping
  requests, account-scope changes, coalescing, and failure retry.
- `PushNotificationManagerTests` covers system setup, permission generations,
  authorization-prompt/poll overlap, prompt completion independent of remote
  synchronization, idempotent permission persistence, token synchronization,
  scheduling retry/deduplication, and typed route emission through injected
  effects.
- `AppIconBadgeControllerTests` covers normalization, aggregation, reuse, clock
  rollback, overflow saturation, coalescing, local-mutation and reset fencing,
  failure preservation, and retry.
- `NotificationArchitectureTests` enforces effect ownership, compatibility
  facades, local-only account scope, retired aggregate paths, and a 400-line
  production-file ceiling.
- `NotificationSettingsViewModelTests` remains under Profile Settings and locks
  the feature-side permission and remote-registration adapter boundary.

The five Core suites contain 34 deterministic tests. Run them with the five
Profile Settings boundary tests for the 39-test focused matrix:

```sh
xcodebuild test \
  -scheme Merian \
  -project merian.xcodeproj \
  -destination 'id=<booted-simulator-id>' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:merianTests/PushNotificationPolicyTests \
  -only-testing:merianTests/PushRegistrationCoordinatorTests \
  -only-testing:merianTests/PushNotificationManagerTests \
  -only-testing:merianTests/AppIconBadgeControllerTests \
  -only-testing:merianTests/NotificationArchitectureTests \
  -only-testing:merianTests/NotificationSettingsViewModelTests
```

Also run the complete `merianTests` target plus project generation, source
membership, generic build, event-routing, SwiftLint, Markdown-format, and
whitespace gates. Physical-device acceptance still covers real permission
prompts, APNs registration/delivery, lock-screen actions and attachments,
Focus/time-sensitive behavior, foreground suppression, and Home Screen badge
updates.

The canonical surrounding contracts are
[Core Managers](../../../../../docs/development-guides/09-core-managers.md),
[event and presentation routing](../../../../../docs/system-architecture/10-event-and-presentation-routing.md),
and the
[notification API contracts](../../../../../docs/backend-and-data/05-api-contracts.md#register-push-device).
