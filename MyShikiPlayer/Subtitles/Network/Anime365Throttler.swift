//
//  Anime365Throttler.swift
//  MyShikiPlayer
//

import Foundation

/// Caps how many subtitle-backend requests may be in flight at once.
///
/// Invariant: `activeCount` is the number of permits currently owned by a caller.
/// A permit is minted only while `activeCount < maxConcurrent`. On release it is either
/// handed straight to the head waiter — the owner changes, the count does not — or it is
/// destroyed and the count drops. A caller cancelled while queued never receives a permit
/// and must therefore never release one. `withPermit` is the only entry point precisely so
/// that acquire and release cannot get out of step.
actor Anime365Throttler {

  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<Bool, Never>
  }

  private let maxConcurrent: Int
  private var activeCount = 0
  private var waiters: [Waiter] = []

  init(maxConcurrent: Int = 5) {
    self.maxConcurrent = maxConcurrent
  }

  // MARK: - Public API

  /// Runs `body` holding exactly one permit, releasing it on every exit path.
  ///
  /// Throws `CancellationError` without running `body` when the task is cancelled while
  /// queued, so closing the player mid-search cannot strand a permit.
  nonisolated func withPermit<T>(_ body: () async throws -> T) async throws -> T {
    guard await acquire() else { throw CancellationError() }
    do {
      let value = try await body()
      await release()
      return value
    } catch {
      await release()
      throw error
    }
  }

  // MARK: - Diagnostics

  /// Permits currently held by callers. Read by tests to assert the invariant.
  var permitsInUse: Int { activeCount }

  /// Callers queued for a permit. Read by tests to assert the invariant.
  var queuedCount: Int { waiters.count }

  // MARK: - Permit bookkeeping

  /// Returns true when a permit was granted, false when the task was cancelled while queued.
  private func acquire() async -> Bool {
    if activeCount < maxConcurrent {
      activeCount += 1
      return true
    }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // The cancellation handler may already have run and found nothing to remove, so
        // re-check here: whichever of the two reaches the actor last resumes the waiter.
        if Task.isCancelled {
          continuation.resume(returning: false)
        } else {
          waiters.append(Waiter(id: id, continuation: continuation))
        }
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  private func release() {
    if waiters.isEmpty {
      activeCount -= 1
    } else {
      waiters.removeFirst().continuation.resume(returning: true)
    }
  }

  private func cancelWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(returning: false)
  }
}
