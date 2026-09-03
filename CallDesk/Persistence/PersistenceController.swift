import CoreData
import Foundation

/// Owns the Core Data stack behind the CallDesk repositories.
///
/// The managed object model is loaded once and shared by every controller so
/// that repeatedly creating containers (previews, tests) never registers the
/// same entity classes twice.
nonisolated final class PersistenceController: @unchecked Sendable {
    private static let modelName = "CallDeskModel"

    /// Loaded once and immutable afterwards, so sharing across threads is safe.
    nonisolated(unsafe) static let sharedModel: NSManagedObjectModel = {
        guard let modelURL = Bundle(for: PersistenceController.self)
            .url(forResource: modelName, withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: modelURL) else {
            preconditionFailure("Unable to load the \(modelName) Core Data model.")
        }
        return model
    }()

    let container: NSPersistentContainer

    /// Represents the one persistent-store load started for this controller.
    /// `loadPersistentStores` is asynchronous, so repository work must await
    /// this task before it uses a managed object context.
    private let storeLoadTask: Task<Bool, Never>

    /// True when the on-disk store could not be opened and the controller
    /// fell back to an in-memory store to keep the app usable.
    private(set) var isRunningOnFallbackStore = false

    /// - Parameter inMemory: When true the store is backed by `/dev/null`,
    ///   keeping previews and tests fully isolated from user data on disk.
    init(inMemory: Bool = false) {
        let container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.sharedModel)
        if inMemory {
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            container.persistentStoreDescriptions = [description]
        }

        self.container = container
        storeLoadTask = Self.makeStoreLoadTask(for: container, inMemory: inMemory)
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Suspends until Core Data has completed loading the persistent store.
    /// This is the only point at which `loadPersistentStores` guarantees that
    /// the stack is ready to accept fetches and saves.
    func waitUntilReady() async {
        isRunningOnFallbackStore = await storeLoadTask.value
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    // MARK: - Crash protection

    /// A corrupted store must never keep the app from launching: the broken
    /// file is destroyed and recreated, and if even that fails the stack
    /// runs in memory for this session. The seed catalog restores a usable
    /// baseline in both cases.
    private static func makeStoreLoadTask(
        for container: NSPersistentContainer,
        inMemory: Bool
    ) -> Task<Bool, Never> {
        Task { @MainActor in
            do {
                try await loadStores(of: container)
                return false
            } catch {
                guard !inMemory else {
                    preconditionFailure("Unable to load the in-memory CallDesk store: \(error)")
                }
                return await recoverFromFailedLoad(of: container)
            }
        }
    }

    private static func recoverFromFailedLoad(of container: NSPersistentContainer) async -> Bool {
        if let storeURL = container.persistentStoreDescriptions.first?.url {
            try? container.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL,
                type: .sqlite
            )
            do {
                try await loadStores(of: container)
                return false
            } catch {
                // Continue into the in-memory fallback below.
            }
        }
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        container.persistentStoreDescriptions = [description]
        do {
            try await loadStores(of: container)
        } catch {
            preconditionFailure("Unable to load the fallback CallDesk store: \(error)")
        }
        return true
    }

    private static func loadStores(of container: NSPersistentContainer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
