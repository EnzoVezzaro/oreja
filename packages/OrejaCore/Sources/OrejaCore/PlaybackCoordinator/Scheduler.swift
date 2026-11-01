import Foundation

@MainActor
public protocol ScheduledAction: AnyObject {
    func cancel()
}

@MainActor
public protocol SilenceScheduling {
    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> any ScheduledAction
}

/// Default scheduler used by the app. Tests inject a manual scheduler instead.
@MainActor
public final class TaskScheduler: SilenceScheduling {
    public init() {}

    public func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        TaskScheduledAction(delay: delay, action: action)
    }
}

@MainActor
public final class TaskScheduledAction: ScheduledAction {
    private var task: Task<Void, Never>?
    private let action: @MainActor () -> Void

    public init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
        self.action = action
        let nanoseconds = UInt64((max(0, delay) * 1_000_000_000).rounded())
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
