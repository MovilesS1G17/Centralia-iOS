import Foundation

/// Bridges `AnalyticsTracking` to the shared `AnalyticsRepository`. Events are
/// buffered and sent in batches, so tracking never waits on the network.
///
/// A batch goes out when `batchSize` events are waiting or `flushInterval`
/// after the first buffered event, whichever comes first. A failed send puts
/// the events back (up to `maxBuffered`, dropping the oldest) and schedules a
/// retry with a growing wait (`retryBaseDelay` doubling up to `maxRetryDelay`),
/// without waiting for another event. While retrying, reaching `batchSize` does
/// not trigger an extra send; an explicit `flush()` always does.
final class BatchingAnalyticsTracker: AnalyticsTracking, @unchecked Sendable {
    /// `POST /v1/analytics/events` accepts at most 100 events per call.
    nonisolated static let maximumBatchSize = 100

    nonisolated(unsafe) private let repository: any AnalyticsRepository
    nonisolated private let batchSize: Int
    nonisolated private let flushInterval: Duration
    nonisolated private let maxBuffered: Int
    nonisolated private let retryBaseDelay: Duration
    nonisolated private let maxRetryDelay: Duration

    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var buffer: [ClientAnalyticsEvent] = []
    nonisolated(unsafe) private var scheduledFlush: Task<Void, Never>?
    nonisolated(unsafe) private var isSending = false
    nonisolated(unsafe) private var retryAttempt = 0

    nonisolated init(
        repository: any AnalyticsRepository,
        batchSize: Int = 20,
        flushInterval: Duration = .seconds(5),
        maxBuffered: Int = 200,
        retryBaseDelay: Duration = .seconds(2),
        maxRetryDelay: Duration = .seconds(60)
    ) {
        self.repository = repository
        self.batchSize = min(max(batchSize, 1), Self.maximumBatchSize)
        self.flushInterval = flushInterval
        self.maxBuffered = max(maxBuffered, self.batchSize)
        self.retryBaseDelay = retryBaseDelay
        self.maxRetryDelay = maxRetryDelay
    }

    nonisolated func track(_ event: ClientAnalyticsEvent) {
        lock.lock()
        buffer.append(event)
        if buffer.count > maxBuffered {
            buffer.removeFirst(buffer.count - maxBuffered)
        }
        let shouldFlushNow = buffer.count >= batchSize && retryAttempt == 0
        let needsSchedule = !shouldFlushNow && scheduledFlush == nil
        if shouldFlushNow {
            scheduledFlush?.cancel()
            scheduledFlush = nil
        }
        if needsSchedule {
            scheduledFlush = Task { [weak self, flushInterval] in
                try? await Task.sleep(for: flushInterval)
                guard !Task.isCancelled else { return }
                await self?.flush()
            }
        }
        lock.unlock()

        if shouldFlushNow {
            Task { [weak self] in await self?.flush() }
        }
    }

    /// Sends everything buffered, in batches of at most `maximumBatchSize`.
    /// Stops at the first failure and keeps the unsent events for later.
    nonisolated func flush() async {
        guard beginSending() else { return }
        defer { endSending() }

        while let batch = takeBatch() {
            do {
                try await repository.record(batch)
                resetRetries()
            } catch {
                restore(batch)
                scheduleRetry()
                return
            }
        }
    }

    /// The wait before retry number `attempt` (0 is the first retry).
    nonisolated static func retryDelay(forAttempt attempt: Int, base: Duration, maximum: Duration) -> Duration {
        let factor = 1 << min(max(attempt, 0), 30)
        return min(base * factor, maximum)
    }

    #if DEBUG
    /// Events waiting to be sent. Only tests need to look at this.
    nonisolated var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }
    #endif

    private nonisolated func beginSending() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isSending else { return false }
        isSending = true
        scheduledFlush = nil
        return true
    }

    private nonisolated func endSending() {
        lock.lock()
        isSending = false
        lock.unlock()
    }

    private nonisolated func takeBatch() -> [ClientAnalyticsEvent]? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let count = min(buffer.count, Self.maximumBatchSize)
        let batch = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        return batch
    }

    private nonisolated func resetRetries() {
        lock.lock()
        retryAttempt = 0
        lock.unlock()
    }

    /// Called after a failed send, while `isSending` is still set.
    private nonisolated func scheduleRetry() {
        lock.lock()
        let delay = Self.retryDelay(forAttempt: retryAttempt, base: retryBaseDelay, maximum: maxRetryDelay)
        retryAttempt += 1
        scheduledFlush?.cancel()
        scheduledFlush = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
        lock.unlock()
    }

    private nonisolated func restore(_ batch: [ClientAnalyticsEvent]) {
        lock.lock()
        buffer.insert(contentsOf: batch, at: 0)
        if buffer.count > maxBuffered {
            buffer.removeFirst(buffer.count - maxBuffered)
        }
        lock.unlock()
    }
}
