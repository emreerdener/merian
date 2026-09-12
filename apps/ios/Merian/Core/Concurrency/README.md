# Core Concurrency

`Core/Concurrency` owns small, domain-neutral concurrency primitives used across
otherwise unrelated layers.

`DetachedWork.swift` is the one reviewed escape from inherited actor context. It
owns two intentionally coupled declarations: `DetachedWorkCategory` makes each
approved use searchable, while `DetachedWork` provides the execution boundary.
`fireAndForget` is for bounded best-effort work whose result has no owner;
`value` retains the detached task and propagates caller cancellation before
returning a value or error.

Prefer structured tasks and domain actors. Do not move database actors, workflow
state, UIKit background execution, retries, or feature policies here. Those
remain with their domain owners.

`MerianTests/Core/Concurrency/DetachedWorkTests.swift` verifies cancellation
propagation. `CoreUtilitiesArchitectureTests` freezes this file as the sole
owner of both declarations and prevents either declaration from returning to
`AppDIContainer` or another aggregate.
