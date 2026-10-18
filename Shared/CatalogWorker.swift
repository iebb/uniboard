import Foundation

/// Keep catalog scans off the UI actor and propagate the caller's cancellation
/// into the detached worker, where the synchronous parsers check Task state.
enum CatalogWorker {
    static func run<Value: Sendable>(_ operation: @escaping @Sendable () -> Value) async -> Value {
        let worker = Task.detached(priority: .userInitiated, operation: operation)
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
