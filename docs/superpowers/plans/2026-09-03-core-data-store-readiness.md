# Core Data Store Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Core Data repositories from using a context before the persistent store has completed loading.

**Architecture:** `PersistenceController` owns one async store-load task and exposes an awaitable readiness boundary. `CoreDataCallDeskStore` awaits that boundary before all scheduled reads and writes; the exceptional batch-seeding path awaits it explicitly. A controlled test gate proves a real fetch cannot enter Core Data early.

**Tech Stack:** Swift 6, Core Data, Swift Testing, Xcode.

**Spec:** `docs/superpowers/specs/2026-09-03-core-data-store-readiness-design.md`

## Global Constraints

- Target iOS 16+ with Swift 6 and Apple Core Data only.
- Keep the app offline-first and leave a fresh store empty unless existing seed options request a catalog.
- Do not change calling-panel business logic or user data.

---

### Task 1: Prove a Core Data fetch waits for store readiness

**Files:**
- Modify: `CallDeskTests/Persistence/CoreDataPersistenceTests.swift`
- Modify: `CallDesk/Persistence/CoreDataCallDeskStore.swift`

**Interfaces:**
- Consumes: `NSManagedObjectContext`, `CoreDataCallDeskStore.fetchWorkspaces()`.
- Produces: an internal initializer accepting `context: NSManagedObjectContext` and `waitForPersistentStore: @Sendable () async -> Void` for controlled readiness testing.

- [x] **Step 1: Write the failing test**

```swift
let store = CoreDataCallDeskStore(
    context: persistence.newBackgroundContext(),
    waitForPersistentStore: { await readinessGate.wait() }
)
let fetch = Task { try await store.fetchWorkspaces() }
for _ in 0..<100 {
    if await readinessGate.waitCallCount == 1 {
        break
    }
    await Task.yield()
}
#expect(await readinessGate.waitCallCount == 1)
await readinessGate.open()
#expect(try await fetch.value == [])
```

The test names the regression: removing the readiness wait from `performRead` leaves `waitCallCount` at zero.

- [x] **Step 2: Run the focused test and verify it fails**

Run:

```bash
xcodebuild test -project CallDesk.xcodeproj -scheme CallDesk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CallDeskTests/CoreDataPersistenceTests
```

Expected: compilation fails because the controlled-readiness initializer does not exist.

- [x] **Step 3: Add only the controlled store initializer and readiness wait**

```swift
private let waitForPersistentStore: @Sendable () async -> Void

init(context: NSManagedObjectContext, waitForPersistentStore: @escaping @Sendable () async -> Void) {
    self.context = context
    self.waitForPersistentStore = waitForPersistentStore
}

private func performRead<Value: Sendable>(
    _ work: @escaping @Sendable () throws -> Value
) async throws -> Value {
    await waitForPersistentStore()
    return try await context.perform {
        do {
            return try work()
        } catch {
            throw RepositoryError(wrapping: error)
        }
    }
}
```

- [x] **Step 4: Re-run the focused test and verify it passes**

Run the Task 1 command. Expected: the new test and existing persistence tests pass.

### Task 2: Connect every production Core Data operation to the real readiness boundary

**Files:**
- Modify: `CallDesk/Persistence/PersistenceController.swift`
- Modify: `CallDesk/Persistence/CoreDataCallDeskStore.swift`
- Test: `CallDeskTests/Persistence/CoreDataPersistenceTests.swift`

**Interfaces:**
- Consumes: `NSPersistentContainer.loadPersistentStores(completionHandler:)`.
- Produces: `PersistenceController.waitUntilReady() async` and the default `CoreDataCallDeskStore.init(persistence:)` readiness closure.

- [x] **Step 1: Replace the synchronous-looking store loader with one shared async task**

```swift
private let storeLoadTask: Task<Bool, Never>

func waitUntilReady() async {
    isRunningOnFallbackStore = await storeLoadTask.value
}
```

The task must resume only from `loadPersistentStores`' completion handler and retain the existing on-disk recovery followed by `/dev/null` fallback behavior.

- [x] **Step 2: Make the production store use that boundary and cover the direct seed path**

```swift
init(persistence: PersistenceController) {
    context = persistence.newBackgroundContext()
    waitForPersistentStore = { await persistence.waitUntilReady() }
}

func seedInitialDataIfNeeded(catalog: CallDeskSampleData.Catalog) async throws -> Bool {
    await waitForPersistentStore()
    // Preserve the existing batched context.perform implementation below this boundary.
}
```

`performWrite` also awaits readiness, covering repository writes and migration.

- [x] **Step 3: Run focused persistence tests and build the Release app**

Run:

```bash
xcodebuild test -project CallDesk.xcodeproj -scheme CallDesk -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:CallDeskTests/CoreDataPersistenceTests
xcodebuild build -project CallDesk.xcodeproj -scheme CallDesk -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```

Expected: both commands exit 0.

- [x] **Step 4: Commit only the readiness fix and its two documents, then push `main`**

```bash
git add CallDesk.xcodeproj/project.pbxproj CallDesk/Persistence/PersistenceController.swift CallDesk/Persistence/CoreDataCallDeskStore.swift CallDeskTests/Persistence/CoreDataPersistenceTests.swift docs/superpowers/specs/2026-09-03-core-data-store-readiness-design.md docs/superpowers/plans/2026-09-03-core-data-store-readiness.md
git commit -m 'fix: wait for Core Data store readiness'
git push origin main
```

Do not stage the user-specific Xcode state file or pre-existing untracked documents.
