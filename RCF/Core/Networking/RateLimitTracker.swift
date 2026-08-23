import Foundation

/// Client-side token-bucket throttle protecting Cloudflare's 1200 req / 5 min budget.
actor RateLimitTracker {
    private var timestamps: [Date] = []
    private let limit: Int
    private let window: TimeInterval

    init(limit: Int = 1200, window: TimeInterval = 300) {
        self.limit = limit
        self.window = window
    }

    /// Requests still available in the current window.
    var remaining: Int {
        prune()
        return max(0, limit - timestamps.count)
    }

    /// Throws when the local budget is exhausted before a request goes out.
    func acquire() async throws {
        prune()
        guard timestamps.count < limit else {
            let oldest = timestamps[0]
            let retryAfter = max(1, oldest.addingTimeInterval(window).timeIntervalSinceNow)
            throw CloudflareError.throttled(retryAfter: retryAfter)
        }
    }

    /// Records a completed request against the budget.
    func record() {
        timestamps.append(.now)
    }

    private func prune() {
        let cutoff = Date.now.addingTimeInterval(-window)
        timestamps.removeAll { $0 < cutoff }
    }
}
