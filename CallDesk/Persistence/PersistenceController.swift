import CoreData
import Dispatch
import Foundation

/// A bounded, privacy-safe launch trace shared by persistence and the first
/// calling screen. It records technical boundaries only; no call text or
/// user-created content enters the trace.
nonisolated final class StartupDiagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    /// A separate serial queue owns persistence and watchdog callbacks. It
    /// deliberately never uses the main actor: when the UI is frozen, the
    /// next launch can still show the last captured boundary.
    private static let persistenceQueue = DispatchQueue(label: "io.wayneho.CallDesk.startup-diagnostics")
    private static let watchdogQueue = DispatchQueue(label: "io.wayneho.CallDesk.startup-watchdog", qos: .utility)
    private static let storageKey = "startupDiagnostics.lastSession"
    private static let retainedPreviousLineCount = 40

    init() {
        let previousLines = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
        lines = Array(previousLines.suffix(Self.retainedPreviousLineCount))
    }

    func append(_ message: String) {
        let timestamp = Date.now.formatted(date: .omitted, time: .standard)
        let linesToPersist: [String]
        lock.lock()
        lines.append("\(timestamp)  \(message)")
        if lines.count > Self.maximumLines {
            lines.removeFirst(lines.count - Self.maximumLines)
        }
        linesToPersist = lines
        lock.unlock()

        Self.persistenceQueue.async {
            UserDefaults.standard.set(linesToPersist, forKey: Self.storageKey)
        }
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    /// Records liveness from an independent dispatch queue. These lines are
    /// saved even if a synchronous task prevents the main actor from updating
    /// the visible loading screen.
    func startWatchdog(buildLabel: String) {
        append("BUILD \(buildLabel) 后台诊断已启动")
        Self.watchdogQueue.asyncAfter(deadline: .now() + .seconds(3)) { [weak self] in
            self?.append("WATCH-01 后台看门狗仍在运行（3 秒）")
        }
        Self.watchdogQueue.asyncAfter(deadline: .now() + .seconds(15)) { [weak self] in
            self?.append("WATCH-02 后台看门狗仍在运行（15 秒）")
        }
    }

    private static let maximumLines = 80
}

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
    let diagnostics: StartupDiagnostics

    /// Represents the one persistent-store load started for this controller.
    /// `loadPersistentStores` is asynchronous, so repository work must await
    /// this task before it uses a managed object context.
    private let storeLoadTask: Task<Bool, Never>

    /// True when the on-disk store could not be opened and the controller
    /// fell back to an in-memory store to keep the app usable.
    private(set) var isRunningOnFallbackStore = false

    /// - Parameter inMemory: When true the store is backed by `/dev/null`,
    ///   keeping previews and tests fully isolated from user data on disk.
    init(inMemory: Bool = false, diagnostics: StartupDiagnostics = StartupDiagnostics()) {
        let container = NSPersistentContainer(name: Self.modelName, managedObjectModel: Self.sharedModel)
        if inMemory {
            let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
            container.persistentStoreDescriptions = [description]
        }

        self.container = container
        self.diagnostics = diagnostics
        diagnostics.append("STORE-01 开始加载本地数据库")
        storeLoadTask = Self.makeStoreLoadTask(for: container, inMemory: inMemory, diagnostics: diagnostics)
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
        inMemory: Bool,
        diagnostics: StartupDiagnostics
    ) -> Task<Bool, Never> {
        Task { @MainActor in
            diagnostics.append("STORE-02 等待 Core Data 存储加载回调")
            do {
                try await loadStores(of: container)
                diagnostics.append("STORE-03 本地数据库已就绪")
                return false
            } catch {
                diagnostics.append("STORE-04 本地数据库加载失败：\(error)")
                guard !inMemory else {
                    preconditionFailure("Unable to load the in-memory CallDesk store: \(error)")
                }
                return await recoverFromFailedLoad(of: container, diagnostics: diagnostics)
            }
        }
    }

    private static func recoverFromFailedLoad(
        of container: NSPersistentContainer,
        diagnostics: StartupDiagnostics
    ) async -> Bool {
        diagnostics.append("STORE-05 尝试重建本地数据库")
        if let storeURL = container.persistentStoreDescriptions.first?.url {
            try? container.persistentStoreCoordinator.destroyPersistentStore(
                at: storeURL,
                type: .sqlite
            )
            do {
                try await loadStores(of: container)
                diagnostics.append("STORE-06 本地数据库重建完成")
                return false
            } catch {
                diagnostics.append("STORE-07 本地数据库重建失败：\(error)")
                // Continue into the in-memory fallback below.
            }
        }
        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))
        container.persistentStoreDescriptions = [description]
        do {
            try await loadStores(of: container)
            diagnostics.append("STORE-08 已切换到临时内存数据库")
        } catch {
            diagnostics.append("STORE-09 临时内存数据库加载失败：\(error)")
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
