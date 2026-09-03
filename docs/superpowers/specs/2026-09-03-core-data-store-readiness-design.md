# Core Data Store Readiness Design

## Problem

On a clean iPhone 8 Plus running iOS 16.7.16, the calling tab can remain in its loading state indefinitely. The failure is device- and launch-timing-dependent: a new install has no user data, so the calling view's first repository fetch is the relevant operation.

`NSPersistentContainer.loadPersistentStores` completes asynchronously. The current `PersistenceController` starts that load but returns before its completion handler runs. Repository work can therefore use a background context before the persistent store has finished loading. Faster simulators and newer devices usually hide that race.

## Goal

No Core Data repository read, write, migration, or initial-data seed may use its context until the controller has received the persistent-store completion callback.

## Design

`PersistenceController` will retain a single asynchronous startup task. It will start store loading once, await the actual completion callback, and keep the existing corrupt-store recovery path inside that task. `waitUntilReady()` will await the shared task, so concurrent callers wait for the same load rather than starting additional loads.

`CoreDataCallDeskStore` will keep the readiness dependency beside its background context. Its read and write scheduling helpers will await readiness before entering `NSManagedObjectContext.perform`. The initial-data seeding method, which currently invokes `context.perform` directly for batched saves, will await the same readiness dependency first. All repository adapters, startup migration, and maintenance already route through this store, so no calling-view-specific retry or timeout is required.

## Validation

Add a Core Data store test with a deliberately closed readiness gate. A workspace fetch must reach the gate and remain blocked until the test opens it, then complete with the real in-memory Core Data result. The test fails before the readiness dependency exists, and would fail if the production read helper stopped waiting.

Run the focused persistence test target and a Release iOS build. The remaining validation is TestFlight on the affected iPhone 8 Plus because this workspace has no iOS 16 simulator runtime or connected physical device.

## Constraints

- iOS 16+, Swift 6, SwiftUI, Core Data; no third-party dependency.
- Preserve empty-desk behavior on a fresh install; this change only sequences storage startup.
- Do not alter calling-panel business logic, call history, or user data.
