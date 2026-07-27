//
//  Anime365ThrottlerTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

// MARK: - Helpers

/// Tracks how many bodies were inside the throttler at the same moment.
private actor ConcurrencyProbe {
  private var current = 0
  private(set) var peak = 0

  func enter() {
    current += 1
    peak = max(peak, current)
  }

  func leave() {
    current -= 1
  }
}

/// Parks callers until `open()` is called, so a test can pin permits in place
/// without leaning on sleep timings.
private actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    let pending = waiters
    waiters.removeAll()
    pending.forEach { $0.resume() }
  }
}

private func waitUntil(timeout: TimeInterval = 5, _ condition: () async -> Bool) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await condition() { return true }
    try? await Task.sleep(nanoseconds: 500_000)
  }
  return await condition()
}

// MARK: - Tests

@Suite("Anime365Throttler")
struct Anime365ThrottlerTests {

  @Test("A burst of callers never exceeds maxConcurrent")
  func respectsConcurrencyLimit() async {
    let throttler = Anime365Throttler(maxConcurrent: 5)
    let probe = ConcurrencyProbe()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<20 {
        group.addTask {
          try? await throttler.withPermit {
            await probe.enter()
            try? await Task.sleep(nanoseconds: 5_000_000)
            await probe.leave()
          }
        }
      }
    }

    let peak = await probe.peak
    #expect(peak <= 5, "throttler handed out \(peak) permits at once")
    #expect(peak > 1, "bodies never overlapped, so the limit was not actually exercised")
    #expect(await throttler.permitsInUse == 0)
    #expect(await throttler.queuedCount == 0)
  }

  @Test("A caller cancelled while queued strands no permit")
  func cancelledWaiterDoesNotStrandPermit() async throws {
    let throttler = Anime365Throttler(maxConcurrent: 2)
    let gate = Gate()

    let holders = (0..<2).map { _ in
      Task { try await throttler.withPermit { await gate.wait() } }
    }
    #expect(await waitUntil { await throttler.permitsInUse == 2 })

    // Every permit is taken and the gate is shut, so these five can only queue.
    let queued = (0..<5).map { _ in
      Task {
        try await throttler.withPermit {
          Issue.record("a waiter cancelled while queued must never receive a permit")
        }
      }
    }
    #expect(await waitUntil { await throttler.queuedCount == 5 })

    queued.forEach { $0.cancel() }
    for task in queued {
      await #expect(throws: CancellationError.self) { try await task.value }
    }
    #expect(await throttler.queuedCount == 0)

    await gate.open()
    for holder in holders { try await holder.value }

    #expect(await throttler.permitsInUse == 0)

    // The whole point: five cancellations must not have burned the two permits.
    for _ in 0..<6 {
      try await throttler.withPermit { }
    }
    #expect(await throttler.permitsInUse == 0)
    #expect(await throttler.queuedCount == 0)
  }

  @Test("A task cancelled before it ever queues is refused a permit")
  func alreadyCancelledCallerIsRefused() async {
    let throttler = Anime365Throttler(maxConcurrent: 1)
    let gate = Gate()

    let holder = Task { try await throttler.withPermit { await gate.wait() } }
    #expect(await waitUntil { await throttler.permitsInUse == 1 })

    let late = Task {
      // Cancellation lands before `acquire` installs its continuation on some runs and
      // after on others; both orderings must resolve to a refusal rather than a hang.
      try await throttler.withPermit { Issue.record("cancelled caller received a permit") }
    }
    late.cancel()
    await #expect(throws: CancellationError.self) { try await late.value }

    await gate.open()
    try? await holder.value

    #expect(await throttler.permitsInUse == 0)
    #expect(await throttler.queuedCount == 0)
  }

  @Test("A permit is released when the body throws")
  func releasesPermitOnThrow() async {
    struct SampleError: Error {}
    let throttler = Anime365Throttler(maxConcurrent: 1)

    await #expect(throws: SampleError.self) {
      try await throttler.withPermit { throw SampleError() }
    }
    #expect(await throttler.permitsInUse == 0)

    // A stranded permit would deadlock this second call.
    let value = try? await throttler.withPermit { 42 }
    #expect(value == 42)
    #expect(await throttler.permitsInUse == 0)
  }
}
