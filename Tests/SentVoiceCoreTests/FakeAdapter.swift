import Foundation
@testable import SentVoiceCore

/// A provider adapter that records what the client asked and lets a test play the provider's part.
final class FakeAdapter: ProviderAdapter, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var registered: [String] = []
    private(set) var unregisterCalls = 0
    private(set) var calls: [CallTarget] = []
    private(set) var hangups: [String] = []
    private(set) var mutes: [(String, Bool)] = []
    private(set) var digits: [(String, String)] = []
    var statsToReturn = CallStats(rttMs: 40, jitterMs: 5, packetLoss: 0.1)
    var registerError: Error?
    var callError: Error?
    private var handler: (@Sendable (String, AdapterCallEvent) -> Void)?
    private var nextCallNumber = 0

    private(set) var numbers: [String?] = []

    func register(credential: String, number: String?) async throws {
        if let registerError { throw registerError }
        lock.lock(); registered.append(credential); numbers.append(number); lock.unlock()
    }

    func unregister() async throws {
        lock.lock(); unregisterCalls += 1; lock.unlock()
    }

    func call(_ target: CallTarget) async throws -> String {
        if let callError { throw callError }
        lock.lock(); defer { lock.unlock() }
        calls.append(target)
        nextCallNumber += 1
        return "call_\(nextCallNumber)"
    }

    func hangup(callId: String) async throws {
        lock.lock(); hangups.append(callId); lock.unlock()
        report(callId, .disconnected(state: .completed, error: nil))
    }

    func mute(callId: String, muted: Bool) throws {
        lock.lock(); mutes.append((callId, muted)); lock.unlock()
        report(callId, .muteChanged(muted))
    }

    func sendDigits(callId: String, digits: String) throws {
        lock.lock(); self.digits.append((callId, digits)); lock.unlock()
    }

    func stats(callId: String) async throws -> CallStats { statsToReturn }

    func setCallEventHandler(_ handler: @escaping @Sendable (String, AdapterCallEvent) -> Void) {
        lock.lock(); self.handler = handler; lock.unlock()
    }

    /// Plays the provider: reports an event for a call.
    func report(_ callId: String, _ event: AdapterCallEvent) {
        let current = lock.locked { handler }
        current?(callId, event)
    }
}

/// Collects events as they arrive.
final class Recorder<Event>: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [Event] = []
    func append(_ event: Event) { lock.lock(); events.append(event); lock.unlock() }
}

extension SentVoiceClient {
    /// A client over a fake adapter and a fake HTTP that answers the token exchange, telemetry accepted.
    static func testClient(adapter: FakeAdapter = FakeAdapter(), http: FakeHTTP? = nil, tokenProvider: @escaping @Sendable () async throws -> String = { "voice.token" }, registerRetries: Int = 0) -> (SentVoiceClient, FakeAdapter, FakeHTTP) {
        let http = http ?? FakeHTTP([FakeHTTP.ok(exchangeBody)])
        let options = SentVoiceOptions(tokenProvider: tokenProvider, baseURL: URL(string: "https://api.example.test")!, registerRetries: registerRetries, telemetryDisabled: true)
        let client = SentVoiceClient(options: options, adapter: adapter, http: http)
        return (client, adapter, http)
    }
}
