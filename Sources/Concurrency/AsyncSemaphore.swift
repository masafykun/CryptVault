import Foundation

/// Minimal async semaphore to cap how many thumbnail jobs run at once.
actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ permits: Int) { self.permits = permits }

    func wait() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        if waiters.isEmpty { permits += 1 }
        else { waiters.removeFirst().resume() }
    }
}
