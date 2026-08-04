import XCTest
@testable import PiWork

@MainActor
final class UserAlertCenterTests: XCTestCase {

    // MARK: - Helpers

    /// A controllable test clock. The center reads "now" through a closure
    /// `now: () -> Date`; the test mutates `currentTime` to advance.
    private final class TestClock {
        var currentTime: Date = Date(timeIntervalSinceReferenceDate: 0)
        func now() -> Date { currentTime }
    }

    /// Captures fired auto-dismiss callbacks so the test can run them
    /// synchronously rather than waiting for `Task.sleep`.
    private final class FakeScheduler: @unchecked Sendable {
        struct Pending {
            let delay: TimeInterval
            let action: @Sendable () -> Void
        }
        private(set) var pending: [Pending] = []

        func schedule(_ delay: TimeInterval, _ action: @escaping @Sendable () -> Void) -> Task<Void, Never> {
            pending.append(Pending(delay: delay, action: action))
            // Return a no-op task; the center only ever calls .cancel() on it,
            // and an immediately-completed task has no observable behavior on cancel.
            return Task {}
        }

        /// Fire the most recently scheduled auto-dismiss (synchronously).
        /// In production order is FIFO, but the center only ever has 0 or 1
        /// pending at a time so we just run the latest.
        func fireLast() {
            guard let last = pending.popLast() else { return }
            last.action()
        }
    }

    private func makeCenter(
        clock: TestClock = TestClock(),
        scheduler: FakeScheduler = FakeScheduler(),
        dedupeWindow: TimeInterval = 5
    ) -> UserAlertCenter {
        UserAlertCenter(
            dedupeWindow: dedupeWindow,
            now: { clock.now() },
            scheduleAutoDismiss: { delay, action in
                scheduler.schedule(delay, action)
            }
        )
    }

    // MARK: - Basic posting

    func test_postFirstAlert_becomesCurrent() {
        let center = makeCenter()
        center.post(.persistenceError(id: "p1", title: "Boom"))
        XCTAssertEqual(center.current?.id, "p1")
    }

    func test_dismissCurrent_clearsWhenQueueEmpty() {
        let center = makeCenter()
        center.post(.persistenceError(id: "p1", title: "Boom"))
        center.dismissCurrent()
        XCTAssertNil(center.current)
    }

    // MARK: - Queue

    func test_secondAlert_queuesBehindFirst() {
        let center = makeCenter()
        center.post(.persistenceError(id: "p1", title: "First"))
        center.post(.persistenceError(id: "p2", title: "Second"))

        // Only the first is showing.
        XCTAssertEqual(center.current?.id, "p1")
        // Dismissing surfaces the next queued.
        center.dismissCurrent()
        XCTAssertEqual(center.current?.id, "p2")
        // And then we're empty.
        center.dismissCurrent()
        XCTAssertNil(center.current)
    }

    /// FIFO ordering — important so a long-running error doesn't get buried
    /// under fresh transient infos.
    func test_queue_isFIFO() {
        let center = makeCenter()
        center.post(.persistenceError(id: "a", title: "A"))
        center.post(.persistenceError(id: "b", title: "B"))
        center.post(.persistenceError(id: "c", title: "C"))

        XCTAssertEqual(center.current?.id, "a")
        center.dismissCurrent()
        XCTAssertEqual(center.current?.id, "b")
        center.dismissCurrent()
        XCTAssertEqual(center.current?.id, "c")
    }

    // MARK: - Dedupe

    /// Same id within the dedupe window must NOT enqueue a second copy.
    func test_dedupe_dropsRepeatWithinWindow() {
        let clock = TestClock()
        let center = makeCenter(clock: clock, dedupeWindow: 5)

        center.post(.persistenceError(id: "dup", title: "First"))
        // Advance < dedupeWindow.
        clock.currentTime.addTimeInterval(2)
        center.post(.persistenceError(id: "dup", title: "Second"))

        XCTAssertEqual(center.current?.id, "dup")
        XCTAssertEqual(center.current?.title, "First", "Re-post must not replace the visible alert")

        center.dismissCurrent()
        XCTAssertNil(center.current, "Second post must have been dropped, queue empty")
    }

    /// Same id AFTER the dedupe window expires must enqueue normally.
    func test_dedupe_allowsRepeatAfterWindow() {
        let clock = TestClock()
        let center = makeCenter(clock: clock, dedupeWindow: 5)

        center.post(.persistenceError(id: "dup", title: "First"))
        // Advance > dedupeWindow.
        clock.currentTime.addTimeInterval(10)
        center.post(.persistenceError(id: "dup", title: "Second"))

        XCTAssertEqual(center.current?.id, "dup")
        XCTAssertEqual(center.current?.title, "First")

        center.dismissCurrent()
        XCTAssertEqual(center.current?.id, "dup")
        XCTAssertEqual(center.current?.title, "Second")
    }

    /// Different ids never collide in the dedupe table.
    func test_dedupe_doesNotCrossIDs() {
        let center = makeCenter(dedupeWindow: 100)
        center.post(.persistenceError(id: "a", title: "A"))
        center.post(.persistenceError(id: "b", title: "B"))

        XCTAssertEqual(center.current?.id, "a")
        center.dismissCurrent()
        XCTAssertEqual(center.current?.id, "b")
    }

    // MARK: - Auto-dismiss

    func test_persistenceError_doesNotAutoDismiss() {
        let scheduler = FakeScheduler()
        let center = makeCenter(scheduler: scheduler)
        center.post(.persistenceError(id: "p", title: "Err"))

        // persistenceError has autoDismissAfter == nil → scheduler not called.
        XCTAssertEqual(scheduler.pending.count, 0)
    }

    func test_warning_schedulesAutoDismiss_andClearsWhenFired() {
        let scheduler = FakeScheduler()
        let center = makeCenter(scheduler: scheduler)
        center.post(.warning(id: "w", title: "Warn"))

        XCTAssertEqual(scheduler.pending.count, 1)
        XCTAssertEqual(scheduler.pending.first?.delay, 8)
        XCTAssertEqual(center.current?.id, "w")

        // Simulate timer firing — banner should clear.
        scheduler.fireLast()
        // The fire calls dismissCurrent on the main actor via Task — wait one runloop.
        let exp = expectation(description: "auto-dismiss propagates")
        Task { @MainActor in exp.fulfill() }
        wait(for: [exp], timeout: 1)
        XCTAssertNil(center.current)
    }

    func test_info_schedulesShorterAutoDismiss() {
        let scheduler = FakeScheduler()
        let center = makeCenter(scheduler: scheduler)
        center.post(.info(id: "i", title: "Info"))

        XCTAssertEqual(scheduler.pending.first?.delay, 4)
    }

    /// When the user manually dismisses, the next queued alert's auto-dismiss
    /// timer must START. Otherwise a queued warning would pile up forever.
    func test_dismissAdvancesQueue_andSchedulesAutoDismissForNext() {
        let scheduler = FakeScheduler()
        let center = makeCenter(scheduler: scheduler)

        center.post(.persistenceError(id: "p", title: "Sticky")) // no timer
        center.post(.warning(id: "w", title: "Auto"))            // timer when shown

        XCTAssertEqual(scheduler.pending.count, 0, "Warning is queued, not yet visible")

        center.dismissCurrent() // surface the warning

        XCTAssertEqual(center.current?.id, "w")
        XCTAssertEqual(scheduler.pending.count, 1)
        XCTAssertEqual(scheduler.pending.first?.delay, 8)
    }
}
