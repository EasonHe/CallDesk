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

    /// True when the on-disk store could not be opened and the controller
    /// fell back to an in-memory store to keep the app usable.
    private(set) var isRunningOnFallbackStore = false

    /// - Parameter inMemory: When true the store is backed by `/dev/null`,
    ///   keeping previews and tests fully isolated from user data on disk.
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.sharedModel)
        if inMemory {
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            container.persistentStoreDescriptions = [description]
        }

        if let loadError = Self.loadStores(of: container) {
            guard !inMemory else {
                preconditionFailure("Unable to load the in-memory CallDesk store: \(loadError)")
            }
            recoverFromFailedLoad()
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
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
    private func recoverFromFailedLoad() {
        if let storeURL = container.persistentStoreDescriptions.first?.url {
            try? container.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL,
                type: .sqlite
            )
            if Self.loadStores(of: container) == nil {
                return
            }
        }
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        container.persistentStoreDescriptions = [description]
        if let fallbackError = Self.loadStores(of: container) {
            preconditionFailure("Unable to load the fallback CallDesk store: \(fallbackError)")
        }
        isRunningOnFallbackStore = true
    }

    private static func loadStores(of container: NSPersistentContainer) -> Error? {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        return loadError
    }
}
