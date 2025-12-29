//
//  RateLimiter.swift
//  SwiftLocalize
//

import Foundation

// MARK: - RateLimiter

/// Token bucket rate limiter for API requests.
public actor RateLimiter {
    // MARK: Lifecycle

    public init(requestsPerMinute: Int) {
        self.requestsPerMinute = requestsPerMinute
        tokens = Double(requestsPerMinute)
        lastRefill = ContinuousClock.now
        refillRate = Double(requestsPerMinute) / 60.0 // tokens per second
    }

    // MARK: Public

    /// Acquire a token, waiting if necessary.
    public func acquire() async {
        refill()

        while tokens < 1 {
            // Wait for token to become available
            let waitTime = (1.0 - tokens) / refillRate
            try? await Task.sleep(for: .seconds(waitTime))
            refill()
        }

        tokens -= 1
    }

    // MARK: Private

    private let requestsPerMinute: Int
    private var tokens: Double
    private var lastRefill: ContinuousClock.Instant
    private let refillRate: Double

    private func refill() {
        let now = ContinuousClock.now
        let elapsed = now - lastRefill
        let elapsedSeconds = Double(elapsed.components.seconds) +
            Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000

        tokens = min(Double(requestsPerMinute), tokens + elapsedSeconds * refillRate)
        lastRefill = now
    }
}
